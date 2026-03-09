import XCTest

@testable import OhMyWorktree

// MARK: - Mock

private final class MockGitExecutor: GitCommandExecuting, @unchecked Sendable {
    var stubbedResult: CommandResult = CommandResult(stdout: "", stderr: "", exitCode: 0)
    var stubbedError: Error?

    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        if let error = stubbedError { throw error }
        return stubbedResult
    }

    func stub(stdout: String, exitCode: Int32 = 0) {
        stubbedResult = CommandResult(stdout: stdout, stderr: "", exitCode: exitCode)
    }

    func stubError(_ error: Error) {
        stubbedError = error
    }
}

// MARK: - Worktree List Parsing Tests

final class WorktreeManagerTests: XCTestCase {

    private var mock: MockGitExecutor!
    private var sut: WorktreeManager!

    override func setUp() {
        super.setUp()
        mock = MockGitExecutor()
        sut = WorktreeManager(executor: mock)
    }

    // MARK: - Single Worktree

    func testListWorktrees_singleBranchWorktree_parsesCorrectly() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo
        HEAD abc1234567890abcdef
        branch refs/heads/main

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "/Users/user/repo")
        XCTAssertEqual(result[0].folderName, "repo")
        XCTAssertEqual(result[0].branch, "main")
        XCTAssertEqual(result[0].commitHash, "abc1234567890abcdef")
        XCTAssertFalse(result[0].isDetached)
        XCTAssertFalse(result[0].isBare)
        XCTAssertFalse(result[0].isLocked)
    }

    // MARK: - refs/heads/ stripping

    func testListWorktrees_branchWithRefsHeadsPrefix_stripsPrefix() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo/feature-branch
        HEAD deadbeef
        branch refs/heads/feature/my-feature

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result[0].branch, "feature/my-feature")
    }

    func testListWorktrees_branchWithoutRefsHeadsPrefix_keepsAsIs() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo
        HEAD deadbeef
        branch main

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result[0].branch, "main")
    }

    // MARK: - Detached HEAD

    func testListWorktrees_detachedHead_setsIsDetached() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo/detached
        HEAD abc1234
        detached

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isDetached)
        XCTAssertNil(result[0].branch)
    }

    // MARK: - Bare Worktree

    func testListWorktrees_bareWorktree_setsIsBare() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo.git
        HEAD 0000000000000000000000000000000000000000
        bare

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isBare)
    }

    // MARK: - Locked Worktree

    func testListWorktrees_lockedWorktree_setsIsLocked() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo/locked-wt
        HEAD abc1234
        branch refs/heads/feature/locked
        locked reason for locking

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isLocked)
    }

    // MARK: - Multiple Worktrees

    func testListWorktrees_multipleWorktrees_parsesAll() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo
        HEAD abc1111
        branch refs/heads/main

        worktree /Users/user/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        worktree /Users/user/worktrees/feature-b
        HEAD abc3333
        detached

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].branch, "main")
        XCTAssertEqual(result[1].branch, "feature/a")
        XCTAssertTrue(result[2].isDetached)
    }

    // MARK: - folderName derivation

    func testListWorktrees_folderName_isLastPathComponent() async throws {
        mock.stub(stdout: """
        worktree /Users/user/oh-my-worktree/workspaces/my-repo/bright-ocean-widget
        HEAD abc1234
        branch refs/heads/feat/widget

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result[0].folderName, "bright-ocean-widget")
    }

    // MARK: - Empty output

    func testListWorktrees_emptyOutput_returnsEmpty() async throws {
        mock.stub(stdout: "")

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    func testListWorktrees_whitespaceOnlyOutput_returnsEmpty() async throws {
        mock.stub(stdout: "\n\n\n")

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Error handling

    func testListWorktrees_nonZeroExitCode_throws() async {
        mock.stub(stdout: "", exitCode: 128)

        await XCTAssertThrowsErrorAsync(
            try await sut.listWorktrees(repositoryPath: "/tmp/repo")
        )
    }

    func testListWorktrees_executorThrows_rethrows() async {
        mock.stubError(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "process failed"]))

        await XCTAssertThrowsErrorAsync(
            try await sut.listWorktrees(repositoryPath: "/tmp/repo")
        )
    }

    // MARK: - gitPull result parsing

    func testGitPull_alreadyUpToDate_returnsAlreadyUpToDate() async throws {
        mock.stub(stdout: "Already up to date.\n")

        let result = try await sut.gitPull(worktreePath: "/tmp/repo")

        XCTAssertTrue(result.alreadyUpToDate)
        XCTAssertEqual(result.summary, "Already up to date.")
    }

    func testGitPull_withChanges_returnsSummaryLine() async throws {
        mock.stub(stdout: """
        remote: Counting objects: 5, done.
        Updating abc1234..def5678
        Fast-forward
        README.md | 2 +-
        3 files changed, 5 insertions(+), 2 deletions(-)

        """)

        let result = try await sut.gitPull(worktreePath: "/tmp/repo")

        XCTAssertFalse(result.alreadyUpToDate)
        XCTAssertEqual(result.summary, "3 files changed, 5 insertions(+), 2 deletions(-)")
    }

    func testGitPull_conflictError_throws() async {
        mock.stub(stdout: "", exitCode: 1)
        mock.stubbedResult = CommandResult(stdout: "", stderr: "CONFLICT (content): Merge conflict in README.md", exitCode: 1)

        await XCTAssertThrowsErrorAsync(
            try await sut.gitPull(worktreePath: "/tmp/repo")
        )
    }
}

// MARK: - Async Assert Helper

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #file,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {}
}
