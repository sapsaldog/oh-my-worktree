import Foundation
import Testing

@testable import OhMyWorktree

// MARK: - Handler-based Mock

final class HandlerMockGitExecutor: GitCommandExecuting, @unchecked Sendable {
    var executedCommands: [[String]] = []
    var handler: (([String]) -> CommandResult)?

    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        executedCommands.append(arguments)
        return handler?(arguments) ?? CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

// MARK: - addWorktreeFromRemoteBranch Orphaned Branch Tests (GitHub #23)

@Suite struct WorktreeManagerRemoteBranchTests {

    let mock: HandlerMockGitExecutor
    let sut: WorktreeManager
    let expectedPath: String

    init() {
        mock = HandlerMockGitExecutor()
        sut = WorktreeManager(executor: mock, fileManager: MockNoOpFileManager())
        expectedPath = WorktreeManager.worktreePath(repositoryPath: "/tmp/repo", folderName: "bright-ocean")
    }

    private func worktreeListOutput(path: String) -> String {
        """
        worktree \(path)
        HEAD deadbeef
        branch refs/heads/fix/foo

        """
    }

    // MARK: - Fallback when local branch already exists

    @Test func addWorktreeFromRemoteBranch_branchAlreadyExists_fallsBackToExistingBranch() async throws {
        mock.handler = { [expectedPath] args in
            if args.contains("-b") && args.contains("fix/foo") {
                return CommandResult(
                    stdout: "",
                    stderr: "fatal: a branch named 'fix/foo' already exists",
                    exitCode: 128
                )
            }
            if args.first == "worktree" && args.contains("add") && !args.contains("-b") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            if args == ["worktree", "list", "--porcelain"] {
                return CommandResult(stdout: self.worktreeListOutput(path: expectedPath), stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let worktree = try await sut.addWorktreeFromRemoteBranch(
            repositoryPath: "/tmp/repo",
            folderName: "bright-ocean",
            localBranch: "fix/foo",
            remoteBranch: "fix/foo",
            startPoint: "refs/omw/pr/10"
        )

        #expect(worktree.branch == "fix/foo")

        let fallbackCommand = mock.executedCommands.first { args in
            args.first == "worktree" && args.contains("add") && !args.contains("-b") && args.contains("fix/foo")
        }
        #expect(fallbackCommand != nil, "Expected a fallback 'git worktree add <path> <branch>' without -b")
    }

    @Test func addWorktreeFromRemoteBranch_otherError_throwsWithoutRetry() async {
        mock.handler = { args in
            if args.contains("-b") {
                return CommandResult(
                    stdout: "",
                    stderr: "fatal: '<path>' is not a valid path",
                    exitCode: 128
                )
            }
            if args == ["worktree", "list", "--porcelain"] {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await #expect(throws: (any Error).self) {
            try await self.sut.addWorktreeFromRemoteBranch(
                repositoryPath: "/tmp/repo",
                folderName: "bright-ocean",
                localBranch: "fix/foo",
                remoteBranch: "fix/foo",
                startPoint: "refs/omw/pr/10"
            )
        }

        let fallbackCommand = mock.executedCommands.first { args in
            args.first == "worktree" && args.contains("add") && !args.contains("-b")
        }
        #expect(fallbackCommand == nil, "Should not retry with fallback for non-branch-exists errors")
    }

    @Test func addWorktreeFromRemoteBranch_noBranchConflict_usesCreateBranch() async throws {
        mock.handler = { [expectedPath] args in
            if args == ["worktree", "list", "--porcelain"] {
                return CommandResult(stdout: self.worktreeListOutput(path: expectedPath), stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let worktree = try await sut.addWorktreeFromRemoteBranch(
            repositoryPath: "/tmp/repo",
            folderName: "bright-ocean",
            localBranch: "fix/foo",
            remoteBranch: "fix/foo",
            startPoint: "refs/omw/pr/10"
        )

        #expect(worktree.branch == "fix/foo")

        let createBranchCommand = mock.executedCommands.first { args in
            args.contains("-b") && args.contains("fix/foo")
        }
        #expect(createBranchCommand != nil, "Should use -b to create a new branch when none exists")

        let fallbackCommand = mock.executedCommands.first { args in
            args.first == "worktree" && args.contains("add") && !args.contains("-b") && args.contains("fix/foo")
        }
        #expect(fallbackCommand == nil, "Should not issue fallback when -b succeeds")
    }
}
