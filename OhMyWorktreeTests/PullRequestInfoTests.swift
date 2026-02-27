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

    // MARK: - PullRequestState

    func testPullRequestState_rawValues() {
        XCTAssertEqual(PullRequestState(rawValue: "OPEN"), .open)
        XCTAssertEqual(PullRequestState(rawValue: "MERGED"), .merged)
        XCTAssertEqual(PullRequestState(rawValue: "CLOSED"), .closed)
        XCTAssertNil(PullRequestState(rawValue: "DRAFT"))
    }
}
