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

    // MARK: - displayLabel

    func testDisplayLabel_removeWorktree_nonForce() {
        let kind = BackgroundJobKind.removeWorktree(force: false)
        XCTAssertEqual(kind.displayLabel, "Remove")
    }

    func testDisplayLabel_removeWorktree_force() {
        let kind = BackgroundJobKind.removeWorktree(force: true)
        XCTAssertEqual(kind.displayLabel, "Force Remove")
    }

    func testDisplayLabel_pull() {
        let kind = BackgroundJobKind.pull
        XCTAssertEqual(kind.displayLabel, "Git Pull")
    }

    func testDisplayLabel_addWorktreeFromPR_includesPRNumber() {
        let kind = BackgroundJobKind.addWorktreeFromPR(
            remoteBranch: "feature/foo",
            localBranch: "feature/foo",
            prNumber: 42
        )
        XCTAssertEqual(kind.displayLabel, "Import PR #42")
    }

    // MARK: - quickRemove displayLabel

    func testDisplayLabel_quickRemove() {
        let kind = BackgroundJobKind.quickRemove
        XCTAssertEqual(kind.displayLabel, "Quick Remove")
    }

    // MARK: - failureMessage

    func testFailureMessage_allKinds() {
        XCTAssertEqual(BackgroundJobKind.removeWorktree(force: false).failureMessage, "remove failed")
        XCTAssertEqual(BackgroundJobKind.pull.failureMessage, "pull failed")
        XCTAssertEqual(
            BackgroundJobKind.addWorktreeFromPR(
                remoteBranch: "b", localBranch: "b", prNumber: 1
            ).failureMessage,
            "import failed"
        )
    }

    func testFailureMessage_quickRemove() {
        XCTAssertEqual(BackgroundJobKind.quickRemove.failureMessage, "quick remove failed")
    }
}
