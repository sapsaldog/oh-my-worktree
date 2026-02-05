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

    var displayName: String {
        branch ?? "Detached (\(commitHash.prefix(7)))"
    }

    init(
        id: UUID = UUID(),
        path: String,
        folderName: String,
        branch: String? = nil,
        commitHash: String = "",
        isDetached: Bool = false,
        isBare: Bool = false,
        isLocked: Bool = false
    ) {
        self.id = id
        self.path = path
        self.folderName = folderName
        self.branch = branch
        self.commitHash = commitHash
        self.isDetached = isDetached
        self.isBare = isBare
        self.isLocked = isLocked
    }
}
