import XCTest

@testable import OhMyWorktree

// MARK: - BackgroundJobState Tests

final class BackgroundJobStateTests: XCTestCase {

    func testIsActive_pending() {
        XCTAssertTrue(BackgroundJobState.pending.isActive)
    }

    func testIsActive_inProgress() {
        XCTAssertTrue(BackgroundJobState.inProgress.isActive)
    }

    func testIsActive_completed() {
        XCTAssertFalse(BackgroundJobState.completed.isActive)
    }

    func testIsActive_failed() {
        XCTAssertFalse(BackgroundJobState.failed("error").isActive)
    }

    func testIsActive_cancelled() {
        XCTAssertFalse(BackgroundJobState.cancelled.isActive)
    }

    func testIsTerminal_isOppositeOfIsActive() {
        XCTAssertTrue(BackgroundJobState.completed.isTerminal)
        XCTAssertTrue(BackgroundJobState.failed("error").isTerminal)
        XCTAssertTrue(BackgroundJobState.cancelled.isTerminal)
        XCTAssertFalse(BackgroundJobState.pending.isTerminal)
        XCTAssertFalse(BackgroundJobState.inProgress.isTerminal)
    }
}
