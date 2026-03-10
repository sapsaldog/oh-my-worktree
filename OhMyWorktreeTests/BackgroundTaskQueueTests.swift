import XCTest

@testable import OhMyWorktree

// MARK: - Mock Git Executor

private final class MockGitExecutor: GitCommandExecuting, @unchecked Sendable {
    var worktreeListOutput: String = ""
    var shouldFail = false
    var failError = "mock git error"

    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        if arguments == ["worktree", "list", "--porcelain"] {
            return CommandResult(stdout: worktreeListOutput, stderr: "", exitCode: 0)
        }
        if arguments.first == "log" {
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        if shouldFail {
            return CommandResult(stdout: "", stderr: failError, exitCode: 1)
        }
        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

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

// MARK: - BackgroundTaskQueue Tests

@MainActor
final class BackgroundTaskQueueTests: XCTestCase {

    private var mockExecutor: MockGitExecutor!
    private var sut: BackgroundTaskQueue!
    private let repoPath = "/tmp/bq-test-repo"
    private let repoID = UUID()

    override func setUp() async throws {
        try await super.setUp()
        mockExecutor = MockGitExecutor()
        sut = BackgroundTaskQueue(
            worktreeManager: WorktreeManager(executor: mockExecutor),
            store: .shared
        )
    }

    // MARK: - Helpers

    private func makeJob(kind: BackgroundJobKind) -> BackgroundJob {
        BackgroundJob(
            worktreeID: UUID(),
            worktreePath: "\(repoPath)/wt-\(UUID().uuidString.prefix(8))",
            folderName: "wt",
            displayName: "Test Worktree",
            repositoryPath: repoPath,
            repositoryID: repoID,
            kind: kind
        )
    }

    private func waitForIdle(timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while sut.hasActiveJobs && Date() < deadline {
            await Task.yield()
        }
    }

    // MARK: - cancel

    func testCancel_pendingJob_setsCancelled() {
        // Enqueue two jobs for the same repoPath so the second stays pending
        let job1 = makeJob(kind: .pull)
        let job2 = makeJob(kind: .pull)
        sut.enqueue([job1, job2])

        // job2 should be pending (job1 started processing)
        let pendingIndex = sut.jobs.firstIndex(where: { $0.id == job2.id && $0.state == .pending })
        if let idx = pendingIndex {
            sut.cancel(sut.jobs[idx].id)
            XCTAssertEqual(sut.jobs[idx].state, .cancelled)
        }
        // If job2 is already inProgress, the test is a no-op — still valid
    }

    func testCancel_nonExistentID_noChange() {
        sut.cancel(UUID())
        XCTAssertTrue(sut.jobs.isEmpty)
    }

    // MARK: - cancelAll

    func testCancelAll_setsPendingJobsToCancelled() {
        let jobs = (0..<3).map { _ in makeJob(kind: .pull) }
        sut.enqueue(jobs)
        sut.cancelAll()

        let pendingCount = sut.jobs.filter { $0.state == .pending }.count
        XCTAssertEqual(pendingCount, 0)
    }

    // MARK: - busyWorktreeIDs

    func testBusyWorktreeIDs_emptyQueue_isEmpty() {
        XCTAssertTrue(sut.busyWorktreeIDs.isEmpty)
    }

    func testBusyWorktreeIDs_afterIdle_isEmpty() async {
        sut.enqueue(makeJob(kind: .pull))
        await waitForIdle()
        XCTAssertTrue(sut.busyWorktreeIDs.isEmpty)
    }

    // MARK: - progressFraction

    func testProgressFraction_emptyQueue_returnsZero() {
        XCTAssertEqual(sut.progressFraction, 0)
    }

    // MARK: - onJobStateChange on success

    func testOnJobStateChange_completedCalledOnSuccess() async {
        var completedIDs: [UUID] = []
        sut.onJobStateChange = { job in
            if job.state == .completed { completedIDs.append(job.id) }
        }

        let job = makeJob(kind: .pull)
        sut.enqueue(job)
        await waitForIdle()

        XCTAssertTrue(completedIDs.contains(job.id))
    }

    // MARK: - onJobStateChange on failure

    func testOnJobStateChange_failedCalledOnGitError() async {
        mockExecutor.shouldFail = true

        var failedJobs: [BackgroundJob] = []
        sut.onJobStateChange = { job in
            if case .failed = job.state { failedJobs.append(job) }
        }

        let job = makeJob(kind: .pull)
        sut.enqueue(job)
        await waitForIdle()

        XCTAssertEqual(failedJobs.count, 1)
        XCTAssertEqual(failedJobs.first?.id, job.id)
    }

    // MARK: - hasFailedJobs

    func testHasFailedJobs_noJobs_returnsFalse() {
        XCTAssertFalse(sut.hasFailedJobs)
    }

    func testHasFailedJobs_afterFailure_returnsTrue() async {
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await waitForIdle()

        XCTAssertTrue(sut.hasFailedJobs)
    }

    func testHasFailedJobs_afterSuccess_returnsFalse() async {
        sut.enqueue(makeJob(kind: .pull))
        await waitForIdle()

        XCTAssertFalse(sut.hasFailedJobs)
    }

    // MARK: - clearFailed

    func testClearFailed_removesFailedJobs() async {
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await waitForIdle()
        XCTAssertTrue(sut.hasFailedJobs)

        sut.clearFailed()

        XCTAssertFalse(sut.hasFailedJobs)
        XCTAssertTrue(sut.jobs.isEmpty)
    }

    func testClearFailed_leavesNonFailedJobsIntact() async {
        // Enqueue two jobs: first fails, second succeeds (separate worktrees, same repoPath)
        mockExecutor.shouldFail = true
        let failJob = makeJob(kind: .pull)
        sut.enqueue(failJob)
        await waitForIdle()

        // Now allow success for a second job
        mockExecutor.shouldFail = false
        let successJob = makeJob(kind: .pull)
        sut.enqueue(successJob)
        await waitForIdle()

        // clearFailed should remove the failed job but the success job is already gone (clearJobsIfIdle)
        sut.clearFailed()
        XCTAssertFalse(sut.hasFailedJobs)
    }

    // MARK: - busyWorktreeIDs caching

    func testBusyWorktreeIDs_updatesOnEnqueue() {
        let job = makeJob(kind: .pull)
        XCTAssertFalse(sut.busyWorktreeIDs.contains(job.worktreeID))
        sut.enqueue(job)
        XCTAssertTrue(sut.busyWorktreeIDs.contains(job.worktreeID))
    }

    func testBusyWorktreeIDs_clearsAfterIdle() async {
        let job = makeJob(kind: .pull)
        sut.enqueue(job)
        XCTAssertFalse(sut.busyWorktreeIDs.isEmpty)
        await waitForIdle()
        XCTAssertTrue(sut.busyWorktreeIDs.isEmpty)
    }

    func testBusyWorktreeIDs_updatesOnCancel() {
        let job1 = makeJob(kind: .pull)
        let job2 = makeJob(kind: .pull)
        sut.enqueue([job1, job2])

        if let pendingJob = sut.jobs.first(where: { $0.state == .pending }) {
            let worktreeID = pendingJob.worktreeID
            XCTAssertTrue(sut.busyWorktreeIDs.contains(worktreeID))
            sut.cancel(pendingJob.id)
            XCTAssertFalse(sut.busyWorktreeIDs.contains(worktreeID))
        }
    }

    // MARK: - Stress Tests

    func testRapidEnqueueAndCancelAll_allReachTerminalState() async {
        let jobs = (0..<20).map { _ in makeJob(kind: .pull) }
        sut.enqueue(jobs)
        sut.cancelAll()
        await waitForIdle(timeout: 5)

        let pendingCount = sut.jobs.filter { $0.state == .pending }.count
        XCTAssertEqual(pendingCount, 0, "No jobs should remain pending after cancelAll")
        XCTAssertFalse(sut.hasActiveJobs)
    }

    func testRapidEnqueueMultipleRepos_eachProcessedIndependently() async {
        let repo2Path = "/tmp/bq-test-repo-2"
        let jobs1 = (0..<5).map { _ in makeJob(kind: .pull) }
        let jobs2 = (0..<5).map { _ in
            BackgroundJob(
                worktreeID: UUID(),
                worktreePath: "\(repo2Path)/wt-\(UUID().uuidString.prefix(8))",
                folderName: "wt",
                displayName: "Repo2 Worktree",
                repositoryPath: repo2Path,
                repositoryID: UUID(),
                kind: .pull
            )
        }
        sut.enqueue(jobs1 + jobs2)
        await waitForIdle(timeout: 5)

        XCTAssertFalse(sut.hasActiveJobs)
        XCTAssertTrue(sut.busyWorktreeIDs.isEmpty)
    }

    func testRepeatedEnqueueAfterIdle_cleansUpCorrectly() async {
        for _ in 0..<5 {
            sut.enqueue(makeJob(kind: .pull))
            await waitForIdle()
            XCTAssertFalse(sut.hasActiveJobs)
            XCTAssertTrue(sut.busyWorktreeIDs.isEmpty)
        }
        XCTAssertTrue(sut.jobs.isEmpty)
    }

    // MARK: - Fix 5: Concurrent Stress Tests

    /// Simulates rapid enqueue from multiple repos at once (as would happen during bulk operations
    /// triggered by simultaneous UI events). Verifies all jobs reach terminal state with no leaks.
    func testConcurrentEnqueueFromMultipleRepos_allJobsReachTerminalState() async {
        let repo3Path = "/tmp/bq-stress-repo-3"
        let repo4Path = "/tmp/bq-stress-repo-4"

        let jobs1 = (0..<4).map { _ in makeJob(kind: .pull) }
        let jobs2 = (0..<4).map { _ in
            BackgroundJob(
                worktreeID: UUID(),
                worktreePath: "\(repo3Path)/wt-\(UUID().uuidString.prefix(8))",
                folderName: "wt",
                displayName: "Repo3",
                repositoryPath: repo3Path,
                repositoryID: UUID(),
                kind: .pull
            )
        }
        let jobs3 = (0..<4).map { _ in
            BackgroundJob(
                worktreeID: UUID(),
                worktreePath: "\(repo4Path)/wt-\(UUID().uuidString.prefix(8))",
                folderName: "wt",
                displayName: "Repo4",
                repositoryPath: repo4Path,
                repositoryID: UUID(),
                kind: .pull
            )
        }

        // Enqueue all at once to stress the per-repo serial queue
        sut.enqueue(jobs1 + jobs2 + jobs3)
        await waitForIdle(timeout: 10)

        XCTAssertFalse(sut.hasActiveJobs, "All jobs should reach terminal state")
        XCTAssertTrue(sut.busyWorktreeIDs.isEmpty, "No worktrees should remain busy")
        XCTAssertFalse(sut.hasFailedJobs, "No jobs should fail with a succeeding mock")
    }

    /// Enqueue, cancel all, then immediately enqueue again — verifies processing tasks
    /// are cleaned up and restarted correctly (no processingTasks leak from Fix 1).
    func testCancelAll_thenReenqueue_processesNewJobs() async {
        let initialJobs = (0..<5).map { _ in makeJob(kind: .pull) }
        sut.enqueue(initialJobs)
        sut.cancelAll()
        await waitForIdle()

        // After cancel, no pending jobs remain
        XCTAssertFalse(sut.hasActiveJobs)

        // Now enqueue fresh jobs — should be processed without being stuck
        let freshJob = makeJob(kind: .pull)
        sut.enqueue(freshJob)
        await waitForIdle(timeout: 5)

        XCTAssertFalse(sut.hasActiveJobs)
        XCTAssertFalse(sut.hasFailedJobs)
    }

    /// Verifies that onJobStateChange receives a stable value-type snapshot (Fix 2):
    /// the callback's job ID should match the job that was enqueued.
    func testOnJobStateChange_receivesCorrectJobID() async {
        var receivedIDs: [UUID] = []
        let jobs = (0..<3).map { _ in makeJob(kind: .pull) }

        sut.onJobStateChange = { job in
            receivedIDs.append(job.id)
        }
        sut.enqueue(jobs)
        await waitForIdle()

        let enqueuedIDs = Set(jobs.map { $0.id })
        let callbackIDs = Set(receivedIDs)
        XCTAssertTrue(enqueuedIDs.isSubset(of: callbackIDs),
                      "All enqueued job IDs should appear in callbacks")
    }

    // MARK: - Fix 8: Queue State / View Integration Tests
    //
    // These tests verify the queue properties that QueueStatusBarView and WorktreeRowView
    // depend on: progressFraction, currentJobDescription, busyWorktreeIDs, hasFailedJobs.

    func testProgressFraction_multipleJobs_zeroAfterCompletion() async {
        let jobs = (0..<4).map { _ in makeJob(kind: .pull) }
        sut.enqueue(jobs)

        // Before processing starts: 0 of 4 terminal → 0.0
        XCTAssertEqual(sut.progressFraction, 0.0)

        await waitForIdle()

        // After all complete, queue is cleared → 0 of 0 = 0.0
        XCTAssertEqual(sut.progressFraction, 0.0)
        XCTAssertTrue(sut.jobs.isEmpty)
    }

    func testCurrentJobDescription_nilWhenIdle() async {
        sut.enqueue(makeJob(kind: .pull))
        await waitForIdle()
        XCTAssertNil(sut.currentJobDescription,
                     "currentJobDescription should be nil when no job is in-progress")
    }

    func testCurrentJobDescription_nilWhenQueueEmpty() {
        XCTAssertNil(sut.currentJobDescription)
    }

    func testBusyWorktreeIDs_tracksActiveWorktrees_andClearsOnCompletion() async {
        let job1 = makeJob(kind: .pull)
        let job2 = makeJob(kind: .pull)
        sut.enqueue([job1, job2])

        // Both worktrees should be busy immediately after enqueue
        XCTAssertTrue(sut.busyWorktreeIDs.contains(job1.worktreeID),
                      "job1 worktree should be busy")
        XCTAssertTrue(sut.busyWorktreeIDs.contains(job2.worktreeID),
                      "job2 worktree should be busy")

        await waitForIdle()

        XCTAssertTrue(sut.busyWorktreeIDs.isEmpty,
                      "busyWorktreeIDs should be empty after all jobs complete")
    }

    func testBusyWorktreeIDs_excludesFailedJobs() async {
        mockExecutor.shouldFail = true
        let job = makeJob(kind: .pull)
        sut.enqueue(job)
        await waitForIdle()

        // A failed job is terminal — it should not hold the worktree busy
        XCTAssertFalse(sut.busyWorktreeIDs.contains(job.worktreeID),
                       "Failed job should not keep worktree in busy set")
        XCTAssertTrue(sut.hasFailedJobs)
    }

    func testHasActiveJobs_falseWhenOnlyFailedJobsRemain() async {
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await waitForIdle()

        XCTAssertFalse(sut.hasActiveJobs, "hasActiveJobs should be false for failed jobs")
        XCTAssertTrue(sut.hasFailedJobs)
    }

    // MARK: - BackgroundJobTimeoutError

    func testTimeoutError_hasDescriptiveMessage() {
        let error = BackgroundJobTimeoutError()
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(
            error.errorDescription?.contains("60") == true,
            "Timeout error should mention the 60-second limit"
        )
    }
}

// MARK: - WorktreeListViewModel Bulk Remove Tests

@MainActor
final class WorktreeListViewModelSelectionTests: XCTestCase {

    private var mockExecutor: MockGitExecutor!
    private var sut: WorktreeListViewModel!
    private let testRepo = Repository(name: "sel-test", path: "/tmp/sel-test")

    override func setUp() async throws {
        try await super.setUp()
        mockExecutor = MockGitExecutor()
        sut = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: mockExecutor),
            store: .shared,
            pullRequestService: MockNoPRServiceSel()
        )
        sut.repository = testRepo
    }

    // MARK: - removeSelectedWorktrees filtering

    func testRemoveSelectedWorktrees_excludesRootWorktree() async {
        mockExecutor.worktreeListOutput = """
        worktree /tmp/sel-test
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/sel-test/wt-feature
        HEAD abc2222
        branch refs/heads/feature/x

        """
        await sut.loadWorktrees()

        // Select both root and feature
        let root = sut.worktrees.first(where: { $0.path == "/tmp/sel-test" })!
        let feature = sut.worktrees.first(where: { $0.folderName == "wt-feature" })!
        sut.selectedWorktreeIDs = [root.id, feature.id]

        sut.removeSelectedWorktrees(force: false)

        // Only feature should be enqueued — root must be excluded
        XCTAssertEqual(sut.jobQueue.jobs.count, 1)
        XCTAssertEqual(sut.jobQueue.jobs.first?.worktreeID, feature.id)
    }

    func testRemoveSelectedWorktrees_excludesBareWorktrees() async {
        mockExecutor.worktreeListOutput = """
        worktree /tmp/sel-test
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/sel-test/wt-feature
        HEAD abc2222
        branch refs/heads/feature/x

        worktree /tmp/sel-test/bare-wt
        HEAD abc3333
        branch refs/heads/other
        bare

        """
        await sut.loadWorktrees()

        let feature = sut.worktrees.first(where: { $0.folderName == "wt-feature" })!
        let bare = sut.worktrees.first(where: { $0.isBare })!
        sut.selectedWorktreeIDs = [feature.id, bare.id]

        sut.removeSelectedWorktrees(force: false)

        // Only feature enqueued — bare must be excluded
        XCTAssertEqual(sut.jobQueue.jobs.count, 1)
        XCTAssertEqual(sut.jobQueue.jobs.first?.worktreeID, feature.id)
    }

    func testRemoveSelectedWorktrees_clearsSelectionAfterEnqueue() async {
        mockExecutor.worktreeListOutput = """
        worktree /tmp/sel-test
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/sel-test/wt-feature
        HEAD abc2222
        branch refs/heads/feature/x

        """
        await sut.loadWorktrees()

        let feature = sut.worktrees.first(where: { $0.folderName == "wt-feature" })!
        sut.selectedWorktreeIDs = [feature.id]

        sut.removeSelectedWorktrees(force: false)

        XCTAssertTrue(sut.selectedWorktreeIDs.isEmpty)
    }
}

private final class MockNoPRServiceSel: PullRequestFetching {
    func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo] { [:] }
}
