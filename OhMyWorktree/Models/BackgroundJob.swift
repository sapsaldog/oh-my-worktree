import Foundation

// MARK: - BackgroundJobKind

enum BackgroundJobKind: Equatable {
    case removeWorktree(force: Bool)
    case pull

    var displayLabel: String {
        switch self {
        case .removeWorktree(let force): return force ? "Force Remove" : "Remove"
        case .pull: return "Git Pull"
        }
    }
}

// MARK: - BackgroundJobState

enum BackgroundJobState: Equatable {
    case pending
    case inProgress
    case completed
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .pending, .inProgress: return true
        default: return false
        }
    }

    var isTerminal: Bool { !isActive }
}

// MARK: - BackgroundJob

struct BackgroundJob: Identifiable, Equatable {
    let id: UUID
    let worktreeID: UUID
    let worktreePath: String
    let folderName: String
    let displayName: String
    let repositoryPath: String
    let repositoryID: UUID
    let kind: BackgroundJobKind
    var state: BackgroundJobState
    let enqueuedAt: Date

    init(
        worktreeID: UUID,
        worktreePath: String,
        folderName: String,
        displayName: String,
        repositoryPath: String,
        repositoryID: UUID,
        kind: BackgroundJobKind
    ) {
        self.id = UUID()
        self.worktreeID = worktreeID
        self.worktreePath = worktreePath
        self.folderName = folderName
        self.displayName = displayName
        self.repositoryPath = repositoryPath
        self.repositoryID = repositoryID
        self.kind = kind
        self.state = .pending
        self.enqueuedAt = Date()
    }
}
