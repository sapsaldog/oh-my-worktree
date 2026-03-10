import Foundation

struct WorktreeMetadata: Codable, Hashable, Sendable {
    let folderName: String
    let createdAt: Date
    var lastActivityAt: Date
    var customName: String?
    /// The remote PR branch this worktree was imported from, if any.
    /// Stored so the PR badge can be shown even when the local branch
    /// name differs (e.g. versioned imports like "feature/foo-v2").
    var prRemoteBranch: String?

    init(
        folderName: String,
        createdAt: Date = Date(),
        lastActivityAt: Date? = nil,
        customName: String? = nil,
        prRemoteBranch: String? = nil
    ) {
        self.folderName = folderName
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt ?? createdAt
        self.customName = customName
        self.prRemoteBranch = prRemoteBranch
    }
}
