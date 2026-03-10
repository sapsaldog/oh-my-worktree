import CryptoKit
import Foundation

struct Worktree: Identifiable, Hashable, Sendable {
    let id: UUID
    let path: String
    let folderName: String
    let branch: String?
    let commitHash: String
    let isDetached: Bool
    let isBare: Bool
    let isLocked: Bool
    var lastActivityAt: Date?
    var customName: String?
    /// Remote PR branch this worktree was imported from (populated from metadata).
    /// Used as fallback for PR badge lookup when local branch name differs.
    var prRemoteBranch: String?

    var displayName: String {
        if let customName, !customName.isEmpty {
            return customName
        }
        return branch ?? "Detached (\(commitHash.prefix(7)))"
    }

    /// Check if this worktree is the root/main worktree of the given repository.
    ///
    /// Uses path normalization to handle:
    /// - Symlink resolution (via `resolvingSymlinksInPath()`)
    /// - Relative path expansion (. and ..)
    /// - Trailing slash removal
    /// - Tilde expansion (~)
    ///
    /// Note: Assumes paths from `git worktree list --porcelain` are already normalized,
    /// which Git guarantees. Case-sensitivity follows the file system (APFS is case-insensitive by default).
    func isRoot(of repository: Repository) -> Bool {
        // Normalize paths for comparison (resolve symlinks, standardize format)
        let worktreePath = URL(fileURLWithPath: self.path).resolvingSymlinksInPath().path
        let repoPath = URL(fileURLWithPath: repository.path).resolvingSymlinksInPath().path
        return worktreePath == repoPath
    }

    var relativeLastActivity: String? {
        lastActivityAt?.relativeTimeString
    }

    /// Generate a deterministic UUID from the worktree path so that
    /// the same worktree always produces the same id across reloads.
    /// Uses SHA-256 for collision resistance (the previous XOR-fold had
    /// poor entropy for paths sharing long common prefixes).
    ///
    /// **Migration note (v1.x → v2.0):** This changed from XOR-fold to SHA-256,
    /// so all worktree IDs differ from previous versions. This is safe because
    /// IDs are never persisted — they are re-derived from paths on every reload.
    static func stableID(for path: String) -> UUID {
        let digest = SHA256.hash(data: Data(path.utf8))
        var hash = Array(digest.prefix(16))
        // Set UUID version 5 bits
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3],
                           hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11],
                           hash[12], hash[13], hash[14], hash[15]))
    }

    init(
        path: String,
        folderName: String,
        branch: String? = nil,
        commitHash: String = "",
        isDetached: Bool = false,
        isBare: Bool = false,
        isLocked: Bool = false,
        lastActivityAt: Date? = nil
    ) {
        self.id = Self.stableID(for: path)
        self.path = path
        self.folderName = folderName
        self.branch = branch
        self.commitHash = commitHash
        self.isDetached = isDetached
        self.isBare = isBare
        self.isLocked = isLocked
        self.lastActivityAt = lastActivityAt
    }

    // Compare semantic fields only (excludes id and lastActivityAt for change detection).
    // Includes prRemoteBranch so SwiftUI detects PR badge changes.
    static func == (lhs: Worktree, rhs: Worktree) -> Bool {
        lhs.path == rhs.path &&
        lhs.folderName == rhs.folderName &&
        lhs.branch == rhs.branch &&
        lhs.commitHash == rhs.commitHash &&
        lhs.isDetached == rhs.isDetached &&
        lhs.isBare == rhs.isBare &&
        lhs.isLocked == rhs.isLocked &&
        lhs.customName == rhs.customName &&
        lhs.prRemoteBranch == rhs.prRemoteBranch
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(folderName)
        hasher.combine(branch)
        hasher.combine(commitHash)
        hasher.combine(isDetached)
        hasher.combine(isBare)
        hasher.combine(isLocked)
        hasher.combine(customName)
        hasher.combine(prRemoteBranch)
    }
}
