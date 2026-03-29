import Foundation
import Testing

@testable import OhMyWorktree

@Suite struct PullRequestInfoTests {

    @Test func init_storesAllProperties() {
        let url = URL(string: "https://github.com/user/repo/pull/42")!
        let pr = PullRequestInfo(number: 42, url: url, branch: "feature/login", state: .open)

        #expect(pr.number == 42)
        #expect(pr.url == url)
        #expect(pr.branch == "feature/login")
        #expect(pr.state == .open)
    }

    @Test func init_withMergedState() {
        let pr = PullRequestInfo(number: 10, url: URL(string: "https://example.com/pull/10")!, branch: "fix/bug", state: .merged)
        #expect(pr.state == .merged)
    }

    @Test func init_withClosedState() {
        let pr = PullRequestInfo(number: 20, url: URL(string: "https://example.com/pull/20")!, branch: "old-feature", state: .closed)
        #expect(pr.state == .closed)
    }

    @Test func sendable_canBeSentAcrossConcurrencyBoundaries() async {
        let pr = PullRequestInfo(number: 1, url: URL(string: "https://example.com/pull/1")!, branch: "main", state: .open)

        let result = await Task.detached { pr }.value

        #expect(result.number == pr.number)
        #expect(result.url == pr.url)
        #expect(result.branch == pr.branch)
        #expect(result.state == pr.state)
    }

    // MARK: - New Fields (FR-031)

    @Test func init_newFieldsHaveDefaults() {
        let pr = PullRequestInfo(number: 1, url: URL(string: "https://example.com/pull/1")!, branch: "main", state: .open)

        #expect(pr.title == "")
        #expect(pr.author == "")
        #expect(pr.updatedAt == nil)
        #expect(!pr.isDraft)
    }

    @Test func init_withAllFields() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let pr = PullRequestInfo(
            number: 42,
            url: URL(string: "https://example.com/pull/42")!,
            branch: "feature/x",
            state: .open,
            title: "Add dark mode",
            author: "alice",
            updatedAt: date,
            isDraft: true
        )

        #expect(pr.title == "Add dark mode")
        #expect(pr.author == "alice")
        #expect(pr.updatedAt == date)
        #expect(pr.isDraft)
    }

    @Test func hashable_canBeUsedInSet() {
        let url = URL(string: "https://example.com/pull/1")!
        let pr1 = PullRequestInfo(number: 1, url: url, branch: "main", state: .open)
        let pr2 = PullRequestInfo(number: 1, url: url, branch: "main", state: .open)
        let pr3 = PullRequestInfo(number: 2, url: url, branch: "other", state: .open)

        let set: Set<PullRequestInfo> = [pr1, pr2, pr3]
        #expect(set.count == 2)
    }

    @Test func hashable_canBeUsedAsDictionaryKey() {
        let url = URL(string: "https://example.com/pull/1")!
        let pr = PullRequestInfo(number: 1, url: url, branch: "main", state: .open)

        var dict: [PullRequestInfo: String] = [:]
        dict[pr] = "value"

        #expect(dict[pr] == "value")
    }

    // MARK: - PullRequestState

    @Test func pullRequestState_rawValues() {
        #expect(PullRequestState(rawValue: "OPEN") == .open)
        #expect(PullRequestState(rawValue: "MERGED") == .merged)
        #expect(PullRequestState(rawValue: "CLOSED") == .closed)
        #expect(PullRequestState(rawValue: "DRAFT") == nil)
    }
}
