import Foundation

@testable import OhMyWorktree

// MARK: - Shared Test Mock
// Used by BackgroundTaskQueueTests and WorktreeListViewModelSelectionTests.
// WorktreeManagerTests uses its own local mock with a different stubbing API.

// MARK: - No-op PR Service Mock
// Shared by WorktreeListViewModelTests and WorktreeListViewModelSelectionTests.

final class MockNoPRService: PullRequestFetching {
    func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo] { [:] }
}

// MARK: - Simple Git Executor Mock

final class MockSimpleGitExecutor: GitCommandExecuting, @unchecked Sendable {
    var worktreeListOutput: String = ""
    var shouldFail = false
    var failError = "mock git error"

    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        if arguments == ["worktree", "list", "--porcelain"] {
            return CommandResult(stdout: worktreeListOutput, stderr: "", exitCode: 0)
        }
        if arguments.first == "log" {
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        if shouldFail {
            return CommandResult(stdout: "", stderr: failError, exitCode: 1)
        }
        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

// MARK: - No-op FileManager Mock

/// Always succeeds — used by BackgroundTaskQueue tests where the real FileManager
/// would fail because worktree paths don't exist on disk.
final class MockNoOpFileManager: FileManaging, @unchecked Sendable {
    func fileExists(atPath path: String) -> Bool { true }

    func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        // no-op success
    }
}
