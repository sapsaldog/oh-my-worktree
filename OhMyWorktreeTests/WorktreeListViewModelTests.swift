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

// MARK: - contextMenuActions

extension WorktreeListViewModelTests {

    // MARK: Fixtures

    /// Root worktree — same path as testRepo, cannot be removed
    private var rootWorktree: Worktree {
        Worktree(path: testRepo.path, folderName: "test-repo", branch: "main")
    }

    /// Normal non-root worktree
    private var featureWorktree: Worktree {
        Worktree(path: "/tmp/worktrees/feature-a", folderName: "feature-a", branch: "feature/a")
    }

    /// Another normal non-root worktree
    private var fixWorktree: Worktree {
        Worktree(path: "/tmp/worktrees/fix-b", folderName: "fix-b", branch: "fix/b")
    }

    /// Bare worktree — cannot be removed or pulled
    private var bareWorktree: Worktree {
        Worktree(path: "/tmp/worktrees/bare", folderName: "bare", isBare: true)
    }

    // MARK: Single-item behavior (0 or 1 selected)

    func test_contextMenuActions_nothingSelected_nonRoot_allEnabled() {
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = []

        let actions = sut.contextMenuActions(for: featureWorktree)

        XCTAssertTrue(actions.canOpen)
        XCTAssertTrue(actions.canRename)
        XCTAssertTrue(actions.canGitPull)
        XCTAssertTrue(actions.canRemove)
        XCTAssertTrue(actions.canForceRemove)
        XCTAssertTrue(actions.canShowInFinder)
        XCTAssertTrue(actions.canCopyPath)
    }

    func test_contextMenuActions_singleSelected_nonRoot_allEnabled() {
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = [featureWorktree.id]

        let actions = sut.contextMenuActions(for: featureWorktree)

        XCTAssertTrue(actions.canOpen)
        XCTAssertTrue(actions.canRename)
        XCTAssertTrue(actions.canGitPull)
        XCTAssertTrue(actions.canRemove)
        XCTAssertTrue(actions.canForceRemove)
        XCTAssertTrue(actions.canShowInFinder)
        XCTAssertTrue(actions.canCopyPath)
    }

    func test_contextMenuActions_singleSelected_root_removeDisabled() {
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = [rootWorktree.id]

        let actions = sut.contextMenuActions(for: rootWorktree)

        XCTAssertTrue(actions.canOpen)
        XCTAssertTrue(actions.canRename)
        XCTAssertTrue(actions.canGitPull)
        XCTAssertFalse(actions.canRemove)
        XCTAssertFalse(actions.canForceRemove)
        XCTAssertTrue(actions.canShowInFinder)
        XCTAssertTrue(actions.canCopyPath)
    }

    func test_contextMenuActions_singleSelected_bare_removeAndPullDisabled() {
        sut.worktrees = [rootWorktree, bareWorktree]
        sut.selectedWorktreeIDs = [bareWorktree.id]

        let actions = sut.contextMenuActions(for: bareWorktree)

        XCTAssertTrue(actions.canOpen)
        XCTAssertTrue(actions.canRename)
        XCTAssertFalse(actions.canGitPull)
        XCTAssertFalse(actions.canRemove)
        XCTAssertFalse(actions.canForceRemove)
        XCTAssertTrue(actions.canShowInFinder)
        XCTAssertTrue(actions.canCopyPath)
    }

    // MARK: Multi-select behavior (2+ selected AND right-clicked item is in selection)

    func test_contextMenuActions_multiSelected_noRoot_onlyRemoveEnabled() {
        sut.worktrees = [rootWorktree, featureWorktree, fixWorktree]
        sut.selectedWorktreeIDs = [featureWorktree.id, fixWorktree.id]

        let actions = sut.contextMenuActions(for: featureWorktree)

        XCTAssertFalse(actions.canOpen)
        XCTAssertFalse(actions.canRename)
        XCTAssertFalse(actions.canGitPull)
        XCTAssertTrue(actions.canRemove)
        XCTAssertTrue(actions.canForceRemove)
        XCTAssertFalse(actions.canShowInFinder)
        XCTAssertFalse(actions.canCopyPath)
    }

    func test_contextMenuActions_multiSelected_withRootIncluded_removeDisabled() {
        // Root is in selection → canRemove = false regardless of other removable items
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = [rootWorktree.id, featureWorktree.id]

        let actions = sut.contextMenuActions(for: featureWorktree)

        XCTAssertFalse(actions.canOpen)
        XCTAssertFalse(actions.canRename)
        XCTAssertFalse(actions.canGitPull)
        XCTAssertFalse(actions.canRemove)
        XCTAssertFalse(actions.canForceRemove)
        XCTAssertFalse(actions.canShowInFinder)
        XCTAssertFalse(actions.canCopyPath)
    }

    func test_contextMenuActions_multiSelected_allNonRemovable_removeDisabled() {
        // Root + bare: neither can be removed
        sut.worktrees = [rootWorktree, bareWorktree]
        sut.selectedWorktreeIDs = [rootWorktree.id, bareWorktree.id]

        let actions = sut.contextMenuActions(for: bareWorktree)

        XCTAssertFalse(actions.canOpen)
        XCTAssertFalse(actions.canRename)
        XCTAssertFalse(actions.canGitPull)
        XCTAssertFalse(actions.canRemove)
        XCTAssertFalse(actions.canForceRemove)
        XCTAssertFalse(actions.canShowInFinder)
        XCTAssertFalse(actions.canCopyPath)
    }

    func test_contextMenuActions_multiSelected_rightClickedNotInSelection_singleBehavior() {
        // feature + fix are selected, but we right-click on root (not in selection)
        // → treated as single-item → root rules apply
        sut.worktrees = [rootWorktree, featureWorktree, fixWorktree]
        sut.selectedWorktreeIDs = [featureWorktree.id, fixWorktree.id]

        let actions = sut.contextMenuActions(for: rootWorktree)

        XCTAssertTrue(actions.canOpen)
        XCTAssertTrue(actions.canRename)
        XCTAssertTrue(actions.canGitPull)
        XCTAssertFalse(actions.canRemove)       // root cannot be removed
        XCTAssertFalse(actions.canForceRemove)
        XCTAssertTrue(actions.canShowInFinder)
        XCTAssertTrue(actions.canCopyPath)
    }
}

// MARK: - addWorktreeFromPR

extension WorktreeListViewModelTests {

    func test_addWorktreeFromPR_branchNotCheckedOut_enquesWithSameLocalBranch() {
        sut.worktrees = [rootWorktree]

        let pr = PullRequestInfo(
            number: 1,
            url: URL(string: "https://github.com/user/repo/pull/1")!,
            branch: "feature/new",
            state: .open
        )

        let error = sut.addWorktreeFromPR(pr)

        XCTAssertNil(error)
        XCTAssertEqual(sut.jobQueue.jobs.count, 1)
        guard case .addWorktreeFromPR(let remote, let local) = sut.jobQueue.jobs[0].kind else {
            XCTFail("Expected addWorktreeFromPR job kind")
            return
        }
        XCTAssertEqual(remote, "feature/new")
        XCTAssertEqual(local, "feature/new")
    }

    func test_addWorktreeFromPR_branchAlreadyCheckedOut_enquesWithVersionedLocalBranch() {
        sut.worktrees = [
            rootWorktree,
            Worktree(path: "/tmp/worktrees/feature-a", folderName: "feature-a", branch: "feature/a")
        ]

        let pr = PullRequestInfo(
            number: 2,
            url: URL(string: "https://github.com/user/repo/pull/2")!,
            branch: "feature/a",
            state: .open
        )

        let error = sut.addWorktreeFromPR(pr)

        XCTAssertNil(error)
        XCTAssertEqual(sut.jobQueue.jobs.count, 1)
        guard case .addWorktreeFromPR(let remote, let local) = sut.jobQueue.jobs[0].kind else {
            XCTFail("Expected addWorktreeFromPR job kind")
            return
        }
        XCTAssertEqual(remote, "feature/a")
        XCTAssertEqual(local, "feature/a-v2")
        XCTAssertEqual(sut.jobQueue.jobs[0].folderName, "feature-a-v2")
    }
}

// MARK: - addWorktreeFromPR queue-collision guard

extension WorktreeListViewModelTests {

    /// Enqueueing the same PR twice before the first job completes must produce
    /// distinct folderNames and localBranches (Fix #3).
    func test_addWorktreeFromPR_duplicateEnqueue_secondJobUsesVersionedName() {
        sut.worktrees = [rootWorktree]

        let pr = PullRequestInfo(
            number: 10,
            url: URL(string: "https://github.com/user/repo/pull/10")!,
            branch: "feature/new",
            state: .open
        )

        sut.addWorktreeFromPR(pr)
        // First job is pending — worktrees list hasn't updated yet.
        XCTAssertEqual(sut.jobQueue.jobs.count, 1)

        sut.addWorktreeFromPR(pr)
        XCTAssertEqual(sut.jobQueue.jobs.count, 2)

        let job1 = sut.jobQueue.jobs[0]
        let job2 = sut.jobQueue.jobs[1]
        XCTAssertNotEqual(job1.folderName, job2.folderName,
                          "Second import must use a versioned folder name")
        XCTAssertEqual(job2.folderName, "feature-new-v2")
        guard case .addWorktreeFromPR(_, let local2) = job2.kind else {
            XCTFail("Expected addWorktreeFromPR kind"); return
        }
        XCTAssertEqual(local2, "feature/new-v2")
    }
}

// MARK: - renameWorktree selectedWorktreeSubject

extension WorktreeListViewModelTests {

    /// Renaming a selected worktree must emit selectedWorktreeSubject so the
    /// AppDelegate can update the menu bar title immediately (Fix #4).
    func test_renameWorktree_selectedWorktreeSubjectEmitsUpdatedCustomName() async {
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

        var received: [Worktree?] = []
        let cancellable = sut.selectedWorktreeSubject.sink { received.append($0) }
        defer { cancellable.cancel() }

        await sut.renameWorktree(worktree, newName: "My Feature")

        XCTAssertFalse(received.isEmpty,
                       "selectedWorktreeSubject must emit after rename")
        XCTAssertEqual(received.last??.customName, "My Feature")
    }

    /// Renaming a worktree that is NOT currently selected must not emit the subject.
    func test_renameWorktree_nonSelected_doesNotEmitSubject() async {
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
        // Leave selectedWorktree as nil

        var received: [Worktree?] = []
        let cancellable = sut.selectedWorktreeSubject.sink { received.append($0) }
        defer { cancellable.cancel() }

        await sut.renameWorktree(worktree, newName: "Other")

        XCTAssertTrue(received.isEmpty,
                      "selectedWorktreeSubject must not emit when renamed worktree is not selected")
    }
}

// MARK: - No-op PR Service

private final class MockNoPRService: PullRequestFetching {
    func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo] { [:] }
}
