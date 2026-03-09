import XCTest

@testable import OhMyWorktree

final class PullRequestInfoTests: XCTestCase {

    func testInit_storesAllProperties() {
        let url = URL(string: "https://github.com/user/repo/pull/42")!
        let pr = PullRequestInfo(number: 42, url: url, branch: "feature/login", state: .open)

        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.url, url)
        XCTAssertEqual(pr.branch, "feature/login")
        XCTAssertEqual(pr.state, .open)
    }

    func testInit_withMergedState() {
        let pr = PullRequestInfo(number: 10, url: URL(string: "https://example.com/pull/10")!, branch: "fix/bug", state: .merged)
        XCTAssertEqual(pr.state, .merged)
    }

    func testInit_withClosedState() {
        let pr = PullRequestInfo(number: 20, url: URL(string: "https://example.com/pull/20")!, branch: "old-feature", state: .closed)
        XCTAssertEqual(pr.state, .closed)
    }

    func testSendable_canBeSentAcrossConcurrencyBoundaries() async {
        let pr = PullRequestInfo(number: 1, url: URL(string: "https://example.com/pull/1")!, branch: "main", state: .open)

        let result = await Task.detached { pr }.value

        XCTAssertEqual(result.number, pr.number)
        XCTAssertEqual(result.url, pr.url)
        XCTAssertEqual(result.branch, pr.branch)
        XCTAssertEqual(result.state, pr.state)
    }

    // MARK: - New Fields (FR-031)

    func testInit_newFieldsHaveDefaults() {
        let pr = PullRequestInfo(number: 1, url: URL(string: "https://example.com/pull/1")!, branch: "main", state: .open)

        XCTAssertEqual(pr.title, "")
        XCTAssertEqual(pr.author, "")
        XCTAssertNil(pr.updatedAt)
        XCTAssertFalse(pr.isDraft)
    }

    func testInit_withAllFields() {
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

        XCTAssertEqual(pr.title, "Add dark mode")
        XCTAssertEqual(pr.author, "alice")
        XCTAssertEqual(pr.updatedAt, date)
        XCTAssertTrue(pr.isDraft)
    }

    func testHashable_canBeUsedInSet() {
        let url = URL(string: "https://example.com/pull/1")!
        let pr1 = PullRequestInfo(number: 1, url: url, branch: "main", state: .open)
        let pr2 = PullRequestInfo(number: 1, url: url, branch: "main", state: .open)
        let pr3 = PullRequestInfo(number: 2, url: url, branch: "other", state: .open)

        let set: Set<PullRequestInfo> = [pr1, pr2, pr3]
        XCTAssertEqual(set.count, 2)
    }

    func testHashable_canBeUsedAsDictionaryKey() {
        let url = URL(string: "https://example.com/pull/1")!
        let pr = PullRequestInfo(number: 1, url: url, branch: "main", state: .open)

        var dict: [PullRequestInfo: String] = [:]
        dict[pr] = "value"

        XCTAssertEqual(dict[pr], "value")
    }

    // MARK: - PullRequestState

    func testPullRequestState_rawValues() {
        XCTAssertEqual(PullRequestState(rawValue: "OPEN"), .open)
        XCTAssertEqual(PullRequestState(rawValue: "MERGED"), .merged)
        XCTAssertEqual(PullRequestState(rawValue: "CLOSED"), .closed)
        XCTAssertNil(PullRequestState(rawValue: "DRAFT"))
    }
}
