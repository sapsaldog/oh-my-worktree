import Foundation
import Testing

@testable import OhMyWorktree

// MARK: - Mock

private final class MockPRFetching: PullRequestFetching, @unchecked Sendable {
    var listResult: [PullRequestInfo]? = []

    func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo] { [:] }
    func fetchPullRequestList(repositoryPath: String) async -> [PullRequestInfo]? { listResult }
}

// MARK: - Helpers

@Suite(.serialized) @MainActor
struct ImportPRViewModelTests {

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

    @Test func filteredPRs_openTab_returnsOpenNonDraftOnly() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, state: .open, isDraft: false),
            makePR(number: 2, state: .open, isDraft: true),
            makePR(number: 3, state: .merged),
            makePR(number: 4, state: .closed)
        ]
        sut.selectedTab = .open

        #expect(sut.filteredPRs.map(\.number) == [1])
    }

    @Test func filteredPRs_draftTab_returnsDraftPRsOnly() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, state: .open, isDraft: false),
            makePR(number: 2, state: .open, isDraft: true),
            makePR(number: 3, state: .open, isDraft: true),
            makePR(number: 4, state: .merged)
        ]
        sut.selectedTab = .draft

        let numbers = sut.filteredPRs.map(\.number)
        #expect(Set(numbers) == [2, 3])
    }

    @Test func filteredPRs_closedTab_includesMergedAndClosed() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, state: .open),
            makePR(number: 2, state: .merged),
            makePR(number: 3, state: .closed)
        ]
        sut.selectedTab = .closed

        let numbers = sut.filteredPRs.map(\.number)
        #expect(Set(numbers) == [2, 3])
    }

    @Test func filteredPRs_closedTab_excludesOpen() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, state: .open),
            makePR(number: 2, state: .open, isDraft: true)
        ]
        sut.selectedTab = .closed

        #expect(sut.filteredPRs.isEmpty)
    }

    @Test func filteredPRs_emptyPRList_returnsEmpty() {
        let sut = ImportPRViewModel()
        sut.allPRs = []
        sut.selectedTab = .open

        #expect(sut.filteredPRs.isEmpty)
    }

    // MARK: - Search Filtering

    @Test func filteredPRs_searchByTitle_caseInsensitive() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, title: "Add Dark Mode"),
            makePR(number: 2, title: "Fix memory leak")
        ]
        sut.selectedTab = .open
        sut.searchText = "dark mode"

        #expect(sut.filteredPRs.map(\.number) == [1])
    }

    @Test func filteredPRs_searchByNumber_matchesExact() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 42, title: "Something"),
            makePR(number: 142, title: "Other")
        ]
        sut.selectedTab = .open
        sut.searchText = "42"

        let numbers = sut.filteredPRs.map(\.number)
        #expect(numbers.contains(42))
        #expect(numbers.contains(142))
    }

    @Test func filteredPRs_searchByBranch_matchesPartial() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, branch: "feature/dark-mode", title: "PR 1"),
            makePR(number: 2, branch: "fix/crash", title: "PR 2")
        ]
        sut.selectedTab = .open
        sut.searchText = "dark"

        #expect(sut.filteredPRs.map(\.number) == [1])
    }

    @Test func filteredPRs_emptySearch_returnsAll() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1),
            makePR(number: 2),
            makePR(number: 3)
        ]
        sut.selectedTab = .open
        sut.searchText = ""

        #expect(sut.filteredPRs.count == 3)
    }

    @Test func filteredPRs_searchWithNoMatch_returnsEmpty() {
        let sut = ImportPRViewModel()
        sut.allPRs = [makePR(number: 1, title: "Hello world")]
        sut.selectedTab = .open
        sut.searchText = "zzz"

        #expect(sut.filteredPRs.isEmpty)
    }

    // MARK: - Tab + Search Combined

    @Test func filteredPRs_tabAndSearch_bothApplied() {
        let sut = ImportPRViewModel()
        sut.allPRs = [
            makePR(number: 1, branch: "feature/login", state: .open, isDraft: false),
            makePR(number: 2, branch: "feature/logout", state: .open, isDraft: true),
            makePR(number: 3, branch: "fix/crash", state: .open, isDraft: false)
        ]
        sut.selectedTab = .open
        sut.searchText = "feature"

        // Only open non-draft PRs matching "feature"
        #expect(sut.filteredPRs.map(\.number) == [1])
    }

    // MARK: - Initial State

    @Test func initialState_defaultsToOpenTab() {
        let sut = ImportPRViewModel()
        #expect(sut.selectedTab == .open)
    }

    @Test func initialState_emptySearch() {
        let sut = ImportPRViewModel()
        #expect(sut.searchText.isEmpty)
    }

    @Test func initialState_noSelectedPR() {
        let sut = ImportPRViewModel()
        #expect(sut.selectedPR == nil)
    }

    @Test func initialState_notLoading() {
        let sut = ImportPRViewModel()
        #expect(false == sut.isLoading)
    }

    @Test func initialState_loadFailedFalse() {
        let sut = ImportPRViewModel()
        #expect(false == sut.loadFailed)
    }

    // MARK: - Search/tab clearing selectedPR
    // Selection clearing on search/tab change is handled by ImportPRView's
    // .onChange modifiers (SwiftUI view-layer concern, not ViewModel logic).

    // MARK: - loadPRs (RED: drives protocol injection and loadFailed state)

    @Test func loadPRs_success_populatesAllPRs() async {
        let mock = MockPRFetching()
        mock.listResult = [makePR(number: 1), makePR(number: 2)]
        let sut = ImportPRViewModel(pullRequestService: mock)
        sut.repositoryPath = "/tmp/repo"

        await sut.loadPRs()

        #expect(sut.allPRs.count == 2)
        #expect(false == sut.loadFailed)
    }

    @Test func loadPRs_emptySuccess_doesNotSetLoadFailed() async {
        let mock = MockPRFetching()
        mock.listResult = [] // empty but not an error
        let sut = ImportPRViewModel(pullRequestService: mock)
        sut.repositoryPath = "/tmp/repo"

        await sut.loadPRs()

        #expect(sut.allPRs.isEmpty)
        #expect(false == sut.loadFailed)
    }

    @Test func loadPRs_failure_setsLoadFailed() async {
        let mock = MockPRFetching()
        mock.listResult = nil // nil means error
        let sut = ImportPRViewModel(pullRequestService: mock)
        sut.repositoryPath = "/tmp/repo"

        await sut.loadPRs()

        #expect(sut.loadFailed)
        #expect(sut.allPRs.isEmpty)
    }

    @Test func loadPRs_afterFailure_retrySuccess_clearsLoadFailed() async {
        let mock = MockPRFetching()
        mock.listResult = nil
        let sut = ImportPRViewModel(pullRequestService: mock)
        sut.repositoryPath = "/tmp/repo"

        await sut.loadPRs()
        #expect(sut.loadFailed)

        mock.listResult = [makePR(number: 1)]
        await sut.loadPRs()

        #expect(false == sut.loadFailed)
        #expect(sut.allPRs.count == 1)
    }

    @Test func loadPRs_setsIsLoadingDuringFetch() async {
        // Verify loading state is reset after completion (loadFailed case)
        let mock = MockPRFetching()
        mock.listResult = nil
        let sut = ImportPRViewModel(pullRequestService: mock)
        sut.repositoryPath = "/tmp/repo"

        await sut.loadPRs()

        #expect(false == sut.isLoading)
    }

    // MARK: - retry (RED: verifies retry() actually updates state)

    @Test func retry_afterFailure_updatesState() async throws {
        let mock = MockPRFetching()
        mock.listResult = nil
        let sut = ImportPRViewModel(pullRequestService: mock)
        sut.repositoryPath = "/tmp/repo"

        await sut.loadPRs()
        #expect(sut.loadFailed)

        // Use retry() (not direct loadPRs call) to verify it doesn't self-cancel
        mock.listResult = [makePR(number: 1)]
        sut.retry()

        // Wait for the retry Task to complete
        try await pollUntil { false == sut.loadFailed && false == sut.allPRs.isEmpty }

        #expect(false == sut.loadFailed, "retry() should clear loadFailed on success")
        #expect(sut.allPRs.count == 1, "retry() should populate allPRs")
    }

    // MARK: - relativeTimeString (RED: drives guard for future dates)

    @Test func relativeTimeString_justNow_lessThan60Seconds() {
        let date = Date().addingTimeInterval(-30) // 30 seconds ago
        #expect(date.relativeTimeString == "just now")
    }

    @Test func relativeTimeString_minutes() {
        let date = Date().addingTimeInterval(-90) // 1.5 min ago
        #expect(date.relativeTimeString == "1m ago")
    }

    @Test func relativeTimeString_hours() {
        let date = Date().addingTimeInterval(-7200) // 2 hours ago
        #expect(date.relativeTimeString == "2h ago")
    }

    @Test func relativeTimeString_days() {
        let date = Date().addingTimeInterval(-86400 * 3) // 3 days ago
        #expect(date.relativeTimeString == "3d ago")
    }

    @Test func relativeTimeString_futureDate_returnsJustNow() {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour in the future
        #expect(futureDate.relativeTimeString == "just now")
    }

    @Test func relativeTimeString_months_usesMonthAbbreviation() {
        let date = Date().addingTimeInterval(-86400 * 45) // 45 days ago
        #expect(date.relativeTimeString == "1mo ago")
    }

    @Test func relativeTimeString_oneYear_usesYearFormat() {
        let date = Date().addingTimeInterval(-86400 * 400) // ~13 months ago
        #expect(date.relativeTimeString == "1y ago")
    }

    @Test func relativeTimeString_multipleYears_usesYearFormat() {
        let date = Date().addingTimeInterval(-86400 * 800) // ~2.2 years ago
        #expect(date.relativeTimeString == "2y ago")
    }

    @Test func relativeTimeString_360days_showsOneYear() {
        let date = Date().addingTimeInterval(-86400 * 360) // 360 days -> 12 months
        #expect(date.relativeTimeString == "1y ago")
    }

    // MARK: - loadPRs generation guard (isLoading race)

    @Test func loadPRs_staleCall_doesNotResetIsLoading() async throws {
        // Use a slow mock that lets us interleave two loadPRs calls.
        let slowMock = SlowPRFetching()
        let sut = ImportPRViewModel(pullRequestService: slowMock)
        sut.repositoryPath = "/tmp/repo"

        // Start first load — it will suspend at the await.
        let firstLoad = Task { @MainActor in await sut.loadPRs() }

        // Wait for the first load to reach the suspension point.
        try await pollUntil { slowMock.isSuspended }

        // Start second load — invalidates first load's generation.
        let secondLoad = Task { @MainActor in await sut.loadPRs() }

        // Wait for second load to reach the suspension point.
        try await pollUntil { slowMock.suspendCount >= 2 }

        // Resume first call — it should see generation mismatch.
        slowMock.resume()

        await firstLoad.value

        // After first call returns, isLoading should still be true
        // because the second call (the valid one) is still in progress.
        #expect(sut.isLoading,
                "Stale loadPRs call must not reset isLoading when generation mismatches")

        // Resume second call to clean up.
        slowMock.resume()
        await secondLoad.value
        #expect(false == sut.isLoading)
    }
}

// MARK: - Slow mock for interleaving test

private final class SlowPRFetching: PullRequestFetching, @unchecked Sendable {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()
    private(set) var suspendCount = 0
    var isSuspended: Bool { suspendCount > 0 }

    func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo] { [:] }

    func fetchPullRequestList(repositoryPath: String) async -> [PullRequestInfo]? {
        await withCheckedContinuation { continuation in
            lock.lock()
            continuations.append(continuation)
            suspendCount += 1
            lock.unlock()
        }
        return []
    }

    func resume() {
        lock.lock()
        let cont = continuations.isEmpty ? nil : continuations.removeFirst()
        lock.unlock()
        cont?.resume()
    }
}
