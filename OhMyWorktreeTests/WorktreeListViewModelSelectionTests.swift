import XCTest
@testable import OhMyWorktree

// MARK: - WorktreeListViewModel Bulk Remove Tests

@MainActor
final class WorktreeListViewModelSelectionTests: XCTestCase {

    private var mockExecutor: MockSimpleGitExecutor!
    private var sut: WorktreeListViewModel!
    private let testRepo = Repository(name: "sel-test", path: "/tmp/sel-test")

    override func setUp() async throws {
        try await super.setUp()
        mockExecutor = MockSimpleGitExecutor()
        sut = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: mockExecutor),
            store: .shared,
            pullRequestService: MockNoPRService()
        )
        sut.repository = testRepo
    }

    // MARK: - removeSelectedWorktrees filtering

    func testRemoveSelectedWorktrees_excludesRootWorktree() async {
        mockExecutor.worktreeListOutput = """
        worktree /tmp/sel-test
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/sel-test/wt-feature
        HEAD abc2222
        branch refs/heads/feature/x

        """
        await sut.loadWorktrees()

        let root = sut.worktrees.first(where: { $0.path == "/tmp/sel-test" })!
        let feature = sut.worktrees.first(where: { $0.folderName == "wt-feature" })!
        sut.selectedWorktreeIDs = [root.id, feature.id]

        sut.removeSelectedWorktrees(force: false)

        // Only feature should be enqueued — root must be excluded
        XCTAssertEqual(sut.jobQueue.jobs.count, 1)
        XCTAssertEqual(sut.jobQueue.jobs.first?.worktreeID, feature.id)
    }

    func testRemoveSelectedWorktrees_excludesBareWorktrees() async {
        mockExecutor.worktreeListOutput = """
        worktree /tmp/sel-test
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/sel-test/wt-feature
        HEAD abc2222
        branch refs/heads/feature/x

        worktree /tmp/sel-test/bare-wt
        HEAD abc3333
        branch refs/heads/other
        bare

        """
        await sut.loadWorktrees()

        let feature = sut.worktrees.first(where: { $0.folderName == "wt-feature" })!
        let bare = sut.worktrees.first(where: { $0.isBare })!
        sut.selectedWorktreeIDs = [feature.id, bare.id]

        sut.removeSelectedWorktrees(force: false)

        // Only feature enqueued — bare must be excluded
        XCTAssertEqual(sut.jobQueue.jobs.count, 1)
        XCTAssertEqual(sut.jobQueue.jobs.first?.worktreeID, feature.id)
    }

    func testRemoveSelectedWorktrees_clearsSelectionAfterEnqueue() async {
        mockExecutor.worktreeListOutput = """
        worktree /tmp/sel-test
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/sel-test/wt-feature
        HEAD abc2222
        branch refs/heads/feature/x

        """
        await sut.loadWorktrees()

        let feature = sut.worktrees.first(where: { $0.folderName == "wt-feature" })!
        sut.selectedWorktreeIDs = [feature.id]

        sut.removeSelectedWorktrees(force: false)

        XCTAssertTrue(sut.selectedWorktreeIDs.isEmpty)
    }
}

// MARK: - Test-local Mock

private final class MockNoPRService: PullRequestFetching {
    func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo] { [:] }
}
