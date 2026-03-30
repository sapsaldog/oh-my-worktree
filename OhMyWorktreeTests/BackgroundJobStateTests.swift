import Testing

@testable import OhMyWorktree

@Suite struct BackgroundJobStateTests {

    @Test func isActive_pending() {
        #expect(BackgroundJobState.pending.isActive)
    }

    @Test func isActive_inProgress() {
        #expect(BackgroundJobState.inProgress.isActive)
    }

    @Test func isActive_completed() {
        #expect(false == BackgroundJobState.completed.isActive)
    }

    @Test func isActive_failed() {
        #expect(false == BackgroundJobState.failed("error").isActive)
    }

    @Test func isActive_cancelled() {
        #expect(false == BackgroundJobState.cancelled.isActive)
    }

    @Test func isTerminal_isOppositeOfIsActive() {
        #expect(BackgroundJobState.completed.isTerminal)
        #expect(BackgroundJobState.failed("error").isTerminal)
        #expect(BackgroundJobState.cancelled.isTerminal)
        #expect(false == BackgroundJobState.pending.isTerminal)
        #expect(false == BackgroundJobState.inProgress.isTerminal)
    }

    // MARK: - displayLabel

    @Test func displayLabel_removeWorktree_nonForce() {
        let kind = BackgroundJobKind.removeWorktree(force: false)
        #expect(kind.displayLabel == "Remove")
    }

    @Test func displayLabel_removeWorktree_force() {
        let kind = BackgroundJobKind.removeWorktree(force: true)
        #expect(kind.displayLabel == "Force Remove")
    }

    @Test func displayLabel_pull() {
        let kind = BackgroundJobKind.pull
        #expect(kind.displayLabel == "Git Pull")
    }

    @Test func displayLabel_addWorktreeFromPR_includesPRNumber() {
        let kind = BackgroundJobKind.addWorktreeFromPR(
            remoteBranch: "feature/foo",
            localBranch: "feature/foo",
            prNumber: 42
        )
        #expect(kind.displayLabel == "Import PR #42")
    }

    // MARK: - quickRemove displayLabel

    @Test func displayLabel_quickRemove() {
        let kind = BackgroundJobKind.quickRemove
        #expect(kind.displayLabel == "Quick Remove")
    }

    // MARK: - failureMessage

    @Test func failureMessage_allKinds() {
        #expect(BackgroundJobKind.removeWorktree(force: false).failureMessage == "remove failed")
        #expect(BackgroundJobKind.pull.failureMessage == "pull failed")
        #expect(
            BackgroundJobKind.addWorktreeFromPR(
                remoteBranch: "b", localBranch: "b", prNumber: 1
            ).failureMessage
            == "import failed"
        )
    }

    @Test func failureMessage_quickRemove() {
        #expect(BackgroundJobKind.quickRemove.failureMessage == "quick remove failed")
    }
}
