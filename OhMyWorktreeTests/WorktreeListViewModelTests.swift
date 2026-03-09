import XCTest

@testable import OhMyWorktree

// MARK: - Mock Git Executor for ViewModel Tests

private final class MockWorktreeExecutor: GitCommandExecuting, @unchecked Sendable {
    var worktreeListOutput: String = ""
    var lastCommitTimestamp: String = ""

    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        if arguments == ["worktree", "list", "--porcelain"] {
            return CommandResult(stdout: worktreeListOutput, stderr: "", exitCode: 0)
        }
        if arguments.first == "log" {
            return CommandResult(stdout: lastCommitTimestamp, stderr: "", exitCode: 0)
        }
        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }

    func stubWorktrees(_ porcelainOutput: String) {
        worktreeListOutput = porcelainOutput
    }
}

// MARK: - Tests

@MainActor
final class WorktreeListViewModelTests: XCTestCase {

    private var mockExecutor: MockWorktreeExecutor!
    private var sut: WorktreeListViewModel!
    private let testRepo = Repository(
        name: "test-repo",
        path: "/tmp/test-repo"
    )

    override func setUp() async throws {
        try await super.setUp()
        mockExecutor = MockWorktreeExecutor()
        sut = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: mockExecutor),
            store: .shared,
            pullRequestService: MockNoPRService()
        )
        sut.repository = testRepo
    }

    // MARK: - updateSelectedWorktree (via loadWorktrees)

    func testLoadWorktrees_selectedWorktreeUpdated_whenStillPresent() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        await sut.loadWorktrees()
        sut.selectedWorktree = sut.worktrees.first(where: { $0.folderName == "feature-a" })

        // Reload — selected should still be there, updated with fresh data
        await sut.loadWorktrees()

        XCTAssertNotNil(sut.selectedWorktree)
        XCTAssertEqual(sut.selectedWorktree?.folderName, "feature-a")
    }

    func testLoadWorktrees_selectedWorktreeCleared_whenRemoved() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        await sut.loadWorktrees()
        sut.selectedWorktree = sut.worktrees.first(where: { $0.folderName == "feature-a" })
        XCTAssertNotNil(sut.selectedWorktree)

        // Remove feature-a from the list
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        """)

        await sut.loadWorktrees()

        XCTAssertNil(sut.selectedWorktree)
    }

    // MARK: - loadWorktrees basic behavior

    func testLoadWorktrees_populatesWorktrees() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-x
        HEAD abc2222
        branch refs/heads/feature/x

        """)

        await sut.loadWorktrees()

        XCTAssertEqual(sut.worktrees.count, 2)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }

    func testLoadWorktrees_noRepository_clearsWorktrees() async {
        sut.repository = nil
        mockExecutor.stubWorktrees("worktree /tmp/test-repo\nHEAD abc\nbranch refs/heads/main\n")

        await sut.loadWorktrees()

        XCTAssertTrue(sut.worktrees.isEmpty)
    }

    func testLoadWorktrees_debounce_skipsIfRecentlyLoaded() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        """)

        await sut.loadWorktrees()
        XCTAssertEqual(sut.worktrees.count, 1)

        // Change the stub — debounced call should not re-fetch
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/new-wt
        HEAD abc2222
        branch refs/heads/feature/new

        """)

        await sut.loadWorktrees(debounce: true)

        // Still 1 — debounce skipped the reload
        XCTAssertEqual(sut.worktrees.count, 1)
    }

    // MARK: - renameWorktree

    func testRenameWorktree_updatesLocalState() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        await sut.loadWorktrees()
        let worktree = sut.worktrees.first(where: { $0.folderName == "feature-a" })!
        sut.selectedWorktree = worktree

        await sut.renameWorktree(worktree, newName: "My Feature")

        XCTAssertEqual(sut.worktrees.first(where: { $0.folderName == "feature-a" })?.customName, "My Feature")
        XCTAssertEqual(sut.selectedWorktree?.customName, "My Feature")
    }

    func testRenameWorktree_whitespaceOnlyName_clearsCustomName() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        await sut.loadWorktrees()
        let worktree = sut.worktrees.first(where: { $0.folderName == "feature-a" })!

        await sut.renameWorktree(worktree, newName: "   ")

        XCTAssertNil(sut.worktrees.first(where: { $0.folderName == "feature-a" })?.customName)
    }
}

// MARK: - No-op PR Service

private final class MockNoPRService: PullRequestFetching {
    func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo] { [:] }
}
