import XCTest

@testable import OhMyWorktree

final class PullRequestInfoTests: XCTestCase {

    func testInit_storesAllProperties() {
        let url = URL(string: "https://github.com/user/repo/pull/42")!
        let pr = PullRequestInfo(number: 42, url: url, branch: "feature/login")

        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.url, url)
        XCTAssertEqual(pr.branch, "feature/login")
    }

    func testSendable_canBeSentAcrossConcurrencyBoundaries() async {
        let pr = PullRequestInfo(number: 1, url: URL(string: "https://example.com/pull/1")!, branch: "main")

        let result = await Task.detached { pr }.value

        XCTAssertEqual(result.number, pr.number)
        XCTAssertEqual(result.url, pr.url)
        XCTAssertEqual(result.branch, pr.branch)
    }
}
