import XCTest

@testable import OhMyWorktree

// MARK: - Mock

private final class MockPRFetching: PullRequestFetching, @unchecked Sendable {
    var listResult: [PullRequestInfo]? = []

    func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo] { [:] }
    func fetchPullRequestList(repositoryPath: String) async -> [PullRequestInfo]? { listResult }
}

// MARK: - Helpers

@MainActor
final class ImportPRViewModelTests: XCTestCase {

    private func makePR(
        number: Int,
        branch: String = "branch",
        title: String = "Title",
        author: String = "user",
        state: PullRequestState = .open,
        isDraft: Bool = false
    ) -> PullRequestInfo {
        PullRequestInfo(
            number: number,
            url: URL(string: "https://github.com/user/repo/pull/\(number)")!,
            branch: branch,
            state: state,
            title: title,
            author: author,
            isDraft: isDraft
        )
    }

    // MARK: - Tab Filtering

    func testFilteredPRs_openTab_returnsOpenNonDraftOnly() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, state: .open, isDraft: false),
            makePR(number: 2, state: .open, isDraft: true),
            makePR(number: 3, state: .merged),
            makePR(number: 4, state: .closed)
        ]
        sut.selectedTab = .open

        XCTAssertEqual(sut.filteredPRs.map(\.number), [1])
    }

    func testFilteredPRs_draftTab_returnsDraftPRsOnly() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, state: .open, isDraft: false),
            makePR(number: 2, state: .open, isDraft: true),
            makePR(number: 3, state: .open, isDraft: true),
            makePR(number: 4, state: .merged)
        ]
        sut.selectedTab = .draft

        let numbers = sut.filteredPRs.map(\.number)
        XCTAssertEqual(Set(numbers), [2, 3])
    }

    func testFilteredPRs_closedTab_includesMergedAndClosed() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, state: .open),
            makePR(number: 2, state: .merged),
            makePR(number: 3, state: .closed)
        ]
        sut.selectedTab = .closed

        let numbers = sut.filteredPRs.map(\.number)
        XCTAssertEqual(Set(numbers), [2, 3])
    }

    func testFilteredPRs_closedTab_excludesOpen() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, state: .open),
            makePR(number: 2, state: .open, isDraft: true)
        ]
        sut.selectedTab = .closed

        XCTAssertTrue(sut.filteredPRs.isEmpty)
    }

    func testFilteredPRs_emptyPRList_returnsEmpty() {
        let sut = ImportPRViewModel()
        sut.allPRs = []
        sut.selectedTab = .open

        XCTAssertTrue(sut.filteredPRs.isEmpty)
    }

    // MARK: - Search Filtering

    func testFilteredPRs_searchByTitle_casInsensitive() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, title: "Add Dark Mode"),
            makePR(number: 2, title: "Fix memory leak")
        ]
        sut.selectedTab = .open
        sut.searchText = "dark mode"

        XCTAssertEqual(sut.filteredPRs.map(\.number), [1])
    }

    func testFilteredPRs_searchByNumber_matchesExact() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 42, title: "Something"),
            makePR(number: 142, title: "Other")
        ]
        sut.selectedTab = .open
        sut.searchText = "42"

        let numbers = sut.filteredPRs.map(\.number)
        XCTAssertTrue(numbers.contains(42))
        XCTAssertTrue(numbers.contains(142))
    }

    func testFilteredPRs_searchByBranch_matchesPartial() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, branch: "feature/dark-mode", title: "PR 1"),
            makePR(number: 2, branch: "fix/crash", title: "PR 2")
        ]
        sut.selectedTab = .open
        sut.searchText = "dark"

        XCTAssertEqual(sut.filteredPRs.map(\.number), [1])
    }

    func testFilteredPRs_emptySearch_returnsAll() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1),
            makePR(number: 2),
            makePR(number: 3)
        ]
        sut.selectedTab = .open
        sut.searchText = ""

        XCTAssertEqual(sut.filteredPRs.count, 3)
    }

    func testFilteredPRs_searchWithNoMatch_returnsEmpty() {
        let sut = ImportPRViewModel()
        sut.allPRs = [makePR(number: 1, title: "Hello world")]
        sut.selectedTab = .open
        sut.searchText = "zzz"

        XCTAssertTrue(sut.filteredPRs.isEmpty)
    }

    // MARK: - Tab + Search Combined

    func testFilteredPRs_tabAndSearch_bothApplied() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, branch: "feature/login", state: .open, isDraft: false),
            makePR(number: 2, branch: "feature/logout", state: .open, isDraft: true),
            makePR(number: 3, branch: "fix/crash", state: .open, isDraft: false)
        ]
        sut.selectedTab = .open
        sut.searchText = "feature"

        // Only open non-draft PRs matching "feature"
        XCTAssertEqual(sut.filteredPRs.map(\.number), [1])
    }

    // MARK: - Initial State

    func testInitialState_defaultsToOpenTab() {
        let sut = ImportPRViewModel()
        XCTAssertEqual(sut.selectedTab, .open)
    }

    func testInitialState_emptySearch() {
        let sut = ImportPRViewModel()
        XCTAssertTrue(sut.searchText.isEmpty)
    }

    func testInitialState_noSelectedPR() {
        let sut = ImportPRViewModel()
        XCTAssertNil(sut.selectedPR)
    }

    func testInitialState_notLoading() {
        let sut = ImportPRViewModel()
        XCTAssertFalse(sut.isLoading)
    }

    func testInitialState_loadFailedFalse() {
        let sut = ImportPRViewModel()
        XCTAssertFalse(sut.loadFailed)
    }

    // MARK: - Search clears selectedPR (RED: drives didSet on searchText)

    func testSearchTextChange_clearsSelectedPR() async {
        let sut = ImportPRViewModel()
        sut.allPRs = [makePR(number: 1, title: "Fix bug")]
        sut.selectedPR = makePR(number: 1, title: "Fix bug")

        sut.searchText = "something else"
        await Task.yield() // let the deferred Task in didSet run

        XCTAssertNil(sut.selectedPR)
    }

    func testSearchTextChange_toSameValue_doesNotClearSelectedPR() async {
        let sut = ImportPRViewModel()
        let pr = makePR(number: 1)
        sut.allPRs = [pr]
        sut.searchText = "hello"    // initial set
        await Task.yield()
        sut.selectedPR = pr         // select after initial search

        sut.searchText = "hello"    // same value — must NOT clear
        await Task.yield()

        XCTAssertNotNil(sut.selectedPR)
    }

    func testSearchTextClear_resetsSelectedPR() async {
        let sut = ImportPRViewModel()
        let pr = makePR(number: 1)
        sut.allPRs = [pr]
        sut.selectedPR = pr

        sut.searchText = "xyz"
        await Task.yield()
        XCTAssertNil(sut.selectedPR) // cleared by search change

        // New selection after search works normally
        sut.selectedPR = pr
        sut.searchText = "" // clear search
        await Task.yield()
        XCTAssertNil(sut.selectedPR) // cleared again
    }

    // MARK: - loadPRs (RED: drives protocol injection and loadFailed state)

    func testLoadPRs_success_populatesAllPRs() async {
        let mock = MockPRFetching()
        mock.listResult = [makePR(number: 1), makePR(number: 2)]
        let sut = ImportPRViewModel(pullRequestService: mock)
        sut.repositoryPath = "/tmp/repo"

        await sut.loadPRs()

        XCTAssertEqual(sut.allPRs.count, 2)
        XCTAssertFalse(sut.loadFailed)
    }

    func testLoadPRs_emptySuccess_doesNotSetLoadFailed() async {
        let mock = MockPRFetching()
        mock.listResult = [] // empty but not an error
        let sut = ImportPRViewModel(pullRequestService: mock)
        sut.repositoryPath = "/tmp/repo"

        await sut.loadPRs()

        XCTAssertTrue(sut.allPRs.isEmpty)
        XCTAssertFalse(sut.loadFailed)
    }

    func testLoadPRs_failure_setsLoadFailed() async {
        let mock = MockPRFetching()
        mock.listResult = nil // nil means error
        let sut = ImportPRViewModel(pullRequestService: mock)
        sut.repositoryPath = "/tmp/repo"

        await sut.loadPRs()

        XCTAssertTrue(sut.loadFailed)
        XCTAssertTrue(sut.allPRs.isEmpty)
    }

    func testLoadPRs_afterFailure_retrySuccess_clearsLoadFailed() async {
        let mock = MockPRFetching()
        mock.listResult = nil
        let sut = ImportPRViewModel(pullRequestService: mock)
        sut.repositoryPath = "/tmp/repo"

        await sut.loadPRs()
        XCTAssertTrue(sut.loadFailed)

        mock.listResult = [makePR(number: 1)]
        await sut.loadPRs()

        XCTAssertFalse(sut.loadFailed)
        XCTAssertEqual(sut.allPRs.count, 1)
    }

    func testLoadPRs_setsIsLoadingDuringFetch() async {
        // Verify loading state is reset after completion (loadFailed case)
        let mock = MockPRFetching()
        mock.listResult = nil
        let sut = ImportPRViewModel(pullRequestService: mock)
        sut.repositoryPath = "/tmp/repo"

        await sut.loadPRs()

        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - relativeTimeString (RED: drives guard for future dates)

    func testRelativeTimeString_justNow_lessThan60Seconds() {
        let date = Date().addingTimeInterval(-30) // 30 seconds ago
        XCTAssertEqual(date.relativeTimeString, "just now")
    }

    func testRelativeTimeString_minutes() {
        let date = Date().addingTimeInterval(-90) // 1.5 min ago
        XCTAssertEqual(date.relativeTimeString, "1m ago")
    }

    func testRelativeTimeString_hours() {
        let date = Date().addingTimeInterval(-7200) // 2 hours ago
        XCTAssertEqual(date.relativeTimeString, "2h ago")
    }

    func testRelativeTimeString_days() {
        let date = Date().addingTimeInterval(-86400 * 3) // 3 days ago
        XCTAssertEqual(date.relativeTimeString, "3d ago")
    }

    func testRelativeTimeString_futureDate_returnsJustNow() {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour in the future
        XCTAssertEqual(futureDate.relativeTimeString, "just now")
    }
}
