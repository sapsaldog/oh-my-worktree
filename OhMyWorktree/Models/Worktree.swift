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

    init(
        id: UUID = UUID(),
        path: String,
        folderName: String,
        branch: String? = nil,
        commitHash: String = "",
        isDetached: Bool = false,
        isBare: Bool = false,
        isLocked: Bool = false,
        lastActivityAt: Date? = nil
    ) {
        self.id = id
        self.path = path
        self.folderName = folderName
        self.branch = branch
        self.commitHash = commitHash
        self.isDetached = isDetached
        self.isBare = isBare
        self.isLocked = isLocked
        self.lastActivityAt = lastActivityAt
    }
}
