import Foundation

struct Worktree: Identifiable, Hashable {
    let id: UUID
    let path: String
    let folderName: String
    let branch: String?
    let commitHash: String
    let isDetached: Bool
    let isBare: Bool
    let isLocked: Bool
    var lastActivityAt: Date?

    var displayName: String {
        branch ?? "Detached (\(commitHash.prefix(7)))"
    }

    var relativeLastActivity: String? {
        guard let date = lastActivityAt else { return nil }
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 30 { return "\(days)d ago" }
        let months = days / 30
        return "\(months)M ago"
    }

    /// Generate a deterministic UUID from the worktree path so that
    /// the same worktree always produces the same id across reloads.
    private static func stableID(for path: String) -> UUID {
        let data = Data(path.utf8)
        var hash = [UInt8](repeating: 0, count: 16)
        data.withUnsafeBytes { buffer in
            for (i, byte) in buffer.enumerated() {
                hash[i % 16] ^= byte
            }
        }
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

    // Compare semantic fields only (excludes id and lastActivityAt for change detection)
    static func == (lhs: Worktree, rhs: Worktree) -> Bool {
        lhs.path == rhs.path &&
        lhs.folderName == rhs.folderName &&
        lhs.branch == rhs.branch &&
        lhs.commitHash == rhs.commitHash &&
        lhs.isDetached == rhs.isDetached &&
        lhs.isBare == rhs.isBare &&
        lhs.isLocked == rhs.isLocked
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(folderName)
        hasher.combine(branch)
        hasher.combine(commitHash)
        hasher.combine(isDetached)
        hasher.combine(isBare)
        hasher.combine(isLocked)
    }
}
