import Testing

@testable import OhMyWorktree

@Suite(.serialized)
@MainActor
struct WorktreeListViewModelSearchTests {

    private let mockExecutor: MockSimpleGitExecutor
    private let sut: WorktreeListViewModel
    private let testRepo = Repository(name: "search-test", path: "/tmp/search-test")

    init() async throws {
        mockExecutor = MockSimpleGitExecutor()
        sut = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: mockExecutor, fileManager: MockNoOpFileManager()),
            store: .shared,
            pullRequestService: MockNoPRService()
        )
        sut.repository = testRepo
        mockExecutor.worktreeListOutput = """
        worktree /tmp/search-test
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/search-test/wt-feature
        HEAD abc2222
        branch refs/heads/feature/login

        worktree /tmp/search-test/wt-bugfix
        HEAD abc3333
        branch refs/heads/bugfix/crash

        """
        await sut.loadWorktrees()
    }

    @Test func emptyQueryReturnsAll() {
        sut.searchText = ""
        #expect(sut.filteredWorktrees.count == sut.worktrees.count)
    }

    @Test func whitespaceQueryReturnsAll() {
        sut.searchText = "   "
        #expect(sut.filteredWorktrees.count == sut.worktrees.count)
    }

    @Test func matchesBranchCaseInsensitively() {
        sut.searchText = "LOGIN"
        #expect(sut.filteredWorktrees.map(\.folderName) == ["wt-feature"])
    }

    @Test func matchesFolderName() {
        sut.searchText = "wt-bugfix"
        #expect(sut.filteredWorktrees.map(\.folderName) == ["wt-bugfix"])
    }

    @Test func noMatchReturnsEmpty() {
        sut.searchText = "zzz-nonexistent"
        #expect(sut.filteredWorktrees.isEmpty)
    }
}
