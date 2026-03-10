import Foundation
@testable import OhMyWorktree

// MARK: - Shared Test Mock
// Used by BackgroundTaskQueueTests and WorktreeListViewModelSelectionTests.
// WorktreeManagerTests uses its own local mock with a different stubbing API.

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
