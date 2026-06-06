import Foundation
import Testing

@testable import OhMyWorktree

// Tests for the v2 PR enrichment: reviewDecision + statusCheckRollup parsing,
// exercised through `fetchPullRequests` (the branch-keyed dict used by the detail card).
@Suite struct PullRequestServiceChecksTests {

    private let ghPath = "/usr/local/bin/gh"

    /// Builds a one-PR `gh pr list` payload (branch "feat") with the given extra
    /// review/checks fragment appended to the JSON object, and returns its parsed info.
    private func fetchInfo(extraFields: String) async -> PullRequestInfo? {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:u/r.git")
        let json = """
        [{"number":1,"url":"https://github.com/u/r/pull/1","headRefName":"feat",\
        "state":"OPEN","title":"T","author":{"login":"a"},"updatedAt":null,"isDraft":false\(extraFields)}]
        """
        mock.stubGhPrList(json: json)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)
        return await sut.fetchPullRequests(repositoryPath: "/tmp/r")["feat"]
    }

    // MARK: reviewDecision mapping

    @Test func reviewDecisionMapping() {
        #expect(PullRequestService.parseReviewDecision("APPROVED") == .approved)
        #expect(PullRequestService.parseReviewDecision("CHANGES_REQUESTED") == .changesRequested)
        #expect(PullRequestService.parseReviewDecision("REVIEW_REQUIRED") == .reviewRequired)
        #expect(PullRequestService.parseReviewDecision(nil) == .none)
        #expect(PullRequestService.parseReviewDecision("WHATEVER") == .none)
    }

    @Test func approvedReviewParsedFromJSON() async throws {
        let info = try #require(await fetchInfo(extraFields: ",\"reviewDecision\":\"APPROVED\""))
        #expect(info.reviewDecision == .approved)
    }

    // MARK: statusCheckRollup reduction

    @Test func checksPassing() async throws {
        let info = try #require(await fetchInfo(
            extraFields: ",\"statusCheckRollup\":[{\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]"))
        #expect(info.checkStatus == .passing)
    }

    @Test func checksFailingByConclusion() async throws {
        let info = try #require(await fetchInfo(
            extraFields: ",\"statusCheckRollup\":[{\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}," +
                "{\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"}]"))
        #expect(info.checkStatus == .failing)
    }

    @Test func checksFailingByState() async throws {
        let info = try #require(await fetchInfo(extraFields: ",\"statusCheckRollup\":[{\"state\":\"ERROR\"}]"))
        #expect(info.checkStatus == .failing)
    }

    @Test func checksPendingByStatus() async throws {
        let info = try #require(await fetchInfo(extraFields: ",\"statusCheckRollup\":[{\"status\":\"IN_PROGRESS\"}]"))
        #expect(info.checkStatus == .pending)
    }

    @Test func checksPendingByState() async throws {
        let info = try #require(await fetchInfo(extraFields: ",\"statusCheckRollup\":[{\"state\":\"PENDING\"}]"))
        #expect(info.checkStatus == .pending)
    }

    @Test func checksPendingByExpectedState() async throws {
        let info = try #require(await fetchInfo(extraFields: ",\"statusCheckRollup\":[{\"state\":\"EXPECTED\"}]"))
        #expect(info.checkStatus == .pending)
    }

    @Test func checksNoneWhenEmpty() async throws {
        let info = try #require(await fetchInfo(extraFields: ",\"statusCheckRollup\":[]"))
        #expect(info.checkStatus == .none)
    }

    @Test func checksAndReviewNoneWhenMissing() async throws {
        let info = try #require(await fetchInfo(extraFields: ""))
        #expect(info.checkStatus == .none)
        #expect(info.reviewDecision == .none)
    }
}
