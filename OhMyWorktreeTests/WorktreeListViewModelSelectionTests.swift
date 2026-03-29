import Testing

@testable import OhMyWorktree

// MARK: - WorktreeListViewModel Bulk Remove Tests

@Suite(.serialized)
@MainActor
struct WorktreeListViewModelSelectionTests {

    private let mockExecutor: MockSimpleGitExecutor
    private let sut: WorktreeListViewModel
    private let testRepo = Repository(name: "sel-test", path: "/tmp/sel-test")

    init() async throws {
        mockExecutor = MockSimpleGitExecutor()
        sut = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: mockExecutor, fileManager: MockNoOpFileManager()),
            store: .shared,
            pullRequestService: MockNoPRService()
        )
        sut.repository = testRepo
    }

    // MARK: - removeSelectedWorktrees filtering

    @Test func removeSelectedWorktrees_excludesRootWorktree() async {
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
        #expect(sut.jobQueue.jobs.count == 1)
        #expect(sut.jobQueue.jobs.first?.worktreeID == feature.id)
    }

    @Test func removeSelectedWorktrees_excludesBareWorktrees() async {
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
        #expect(sut.jobQueue.jobs.count == 1)
        #expect(sut.jobQueue.jobs.first?.worktreeID == feature.id)
    }

    @Test func removeSelectedWorktrees_excludesBusyWorktrees() async {
        mockExecutor.worktreeListOutput = """
        worktree /tmp/sel-test
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/sel-test/wt-a
        HEAD abc2222
        branch refs/heads/feature/a

        worktree /tmp/sel-test/wt-b
        HEAD abc3333
        branch refs/heads/feature/b

        """
        await sut.loadWorktrees()

        let wtA = sut.worktrees.first(where: { $0.folderName == "wt-a" })!
        let wtB = sut.worktrees.first(where: { $0.folderName == "wt-b" })!

        // Make wt-a busy by enqueueing a pull job; the processing Task is async
        // so the job stays .pending (busy) until we yield.
        sut.gitPull(wtA)
        #expect(sut.jobQueue.busyWorktreeIDs.contains(wtA.id), "wt-a should be busy")

        sut.selectedWorktreeIDs = [wtA.id, wtB.id]
        sut.removeSelectedWorktrees(force: false)

        // Only wt-b should receive a remove job; wt-a is busy and must be excluded.
        let removeJobs = sut.jobQueue.jobs.filter {
            if case .removeWorktree = $0.kind { return true }
            return false
        }
        #expect(removeJobs.count == 1)
        #expect(removeJobs.first?.worktreeID == wtB.id)
    }

    @Test func removeSelectedWorktrees_clearsSelectionAfterEnqueue() async {
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

        #expect(sut.selectedWorktreeIDs.isEmpty)
    }

    // MARK: - quickRemoveSelectedWorktrees filtering

    @Test func quickRemoveSelectedWorktrees_excludesRootWorktree() async {
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

        sut.quickRemoveSelectedWorktrees()

        let quickJobs = sut.jobQueue.jobs.filter { $0.kind == .quickRemove }
        #expect(quickJobs.count == 1)
        #expect(quickJobs.first?.worktreeID == feature.id)
    }

    @Test func quickRemoveSelectedWorktrees_clearsSelection() async {
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

        sut.quickRemoveSelectedWorktrees()

        #expect(sut.selectedWorktreeIDs.isEmpty)
    }

    @Test func quickRemoveSelectedWorktrees_excludesLockedWorktree() async {
        mockExecutor.worktreeListOutput = """
        worktree /tmp/sel-test
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/sel-test/wt-feature
        HEAD abc2222
        branch refs/heads/feature/x

        worktree /tmp/sel-test/wt-locked
        HEAD abc3333
        branch refs/heads/feature/locked
        locked

        """
        await sut.loadWorktrees()

        let feature = sut.worktrees.first(where: { $0.folderName == "wt-feature" })!
        let locked = sut.worktrees.first(where: { $0.isLocked })!
        sut.selectedWorktreeIDs = [feature.id, locked.id]

        sut.quickRemoveSelectedWorktrees()

        // Only feature should be enqueued — locked must be excluded
        let quickJobs = sut.jobQueue.jobs.filter { $0.kind == .quickRemove }
        #expect(quickJobs.count == 1, "Only non-locked worktree should be quick-removed")
        #expect(quickJobs.first?.worktreeID == feature.id)
    }
}

// MockNoPRService is defined in MockGitExecutor.swift
