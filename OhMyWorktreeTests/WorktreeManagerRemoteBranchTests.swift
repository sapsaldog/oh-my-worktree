import XCTest

@testable import OhMyWorktree

// MARK: - Handler-based Mock

/// Handler-based mock that returns different results based on the git arguments.
private final class HandlerMockGitExecutor: GitCommandExecuting, @unchecked Sendable {
    var executedCommands: [[String]] = []
    var handler: (([String]) -> CommandResult)?

    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        executedCommands.append(arguments)
        return handler?(arguments) ?? CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

// MARK: - addWorktreeFromRemoteBranch Orphaned Branch Tests (GitHub #23)

final class WorktreeManagerRemoteBranchTests: XCTestCase {

    private var mock: HandlerMockGitExecutor!
    private var sut: WorktreeManager!
    private var expectedPath: String!

    override func setUp() {
        super.setUp()
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

    func testAddWorktreeFromRemoteBranch_branchAlreadyExists_fallsBackToExistingBranch() async throws {
        mock.handler = { [expectedPath] args in
            // First call: `git worktree add -b fix/foo <path> <startPoint>` → fails
            if args.contains("-b") && args.contains("fix/foo") {
                return CommandResult(
                    stdout: "",
                    stderr: "fatal: a branch named 'fix/foo' already exists",
                    exitCode: 128
                )
            }
            // Second call: `git worktree add <path> fix/foo` → succeeds
            if args.first == "worktree" && args.contains("add") && !args.contains("-b") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            // Third call: `git worktree list --porcelain` → returns the new worktree
            if args == ["worktree", "list", "--porcelain"] {
                return CommandResult(stdout: self.worktreeListOutput(path: expectedPath!), stderr: "", exitCode: 0)
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

        XCTAssertEqual(worktree.branch, "fix/foo")

        // Verify the fallback command was issued (without -b)
        let fallbackCommand = mock.executedCommands.first { args in
            args.first == "worktree" && args.contains("add") && !args.contains("-b") && args.contains("fix/foo")
        }
        XCTAssertNotNil(fallbackCommand, "Expected a fallback 'git worktree add <path> <branch>' without -b")
    }

    func testAddWorktreeFromRemoteBranch_otherError_throwsWithoutRetry() async {
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

        await XCTAssertThrowsErrorAsync(
            try await sut.addWorktreeFromRemoteBranch(
                repositoryPath: "/tmp/repo",
                folderName: "bright-ocean",
                localBranch: "fix/foo",
                remoteBranch: "fix/foo",
                startPoint: "refs/omw/pr/10"
            )
        )

        // Should NOT attempt a fallback for non-"already exists" errors
        let fallbackCommand = mock.executedCommands.first { args in
            args.first == "worktree" && args.contains("add") && !args.contains("-b")
        }
        XCTAssertNil(fallbackCommand, "Should not retry with fallback for non-branch-exists errors")
    }

    func testAddWorktreeFromRemoteBranch_noBranchConflict_usesCreateBranch() async throws {
        mock.handler = { [expectedPath] args in
            if args == ["worktree", "list", "--porcelain"] {
                return CommandResult(stdout: self.worktreeListOutput(path: expectedPath!), stderr: "", exitCode: 0)
            }
            // All commands succeed (including -b)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let worktree = try await sut.addWorktreeFromRemoteBranch(
            repositoryPath: "/tmp/repo",
            folderName: "bright-ocean",
            localBranch: "fix/foo",
            remoteBranch: "fix/foo",
            startPoint: "refs/omw/pr/10"
        )

        XCTAssertEqual(worktree.branch, "fix/foo")

        // Should use -b (create branch), not fallback
        let createBranchCommand = mock.executedCommands.first { args in
            args.contains("-b") && args.contains("fix/foo")
        }
        XCTAssertNotNil(createBranchCommand, "Should use -b to create a new branch when none exists")

        // Should NOT have a fallback command
        let fallbackCommand = mock.executedCommands.first { args in
            args.first == "worktree" && args.contains("add") && !args.contains("-b") && args.contains("fix/foo")
        }
        XCTAssertNil(fallbackCommand, "Should not issue fallback when -b succeeds")
    }
}
