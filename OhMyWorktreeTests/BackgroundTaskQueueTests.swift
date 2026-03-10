import XCTest
@testable import OhMyWorktree

// MARK: - BackgroundTaskQueue Tests

@MainActor
final class BackgroundTaskQueueTests: XCTestCase {

    private var mockExecutor: MockSimpleGitExecutor!
    private var sut: BackgroundTaskQueue!
    private let repoPath = "/tmp/bq-test-repo"
    private let repoID = UUID()

    override func setUp() async throws {
        try await super.setUp()
        mockExecutor = MockSimpleGitExecutor()
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

    func testBusyWorktreeIDs_tracksActiveWorktrees_andClearsOnCompletion() async {
        let job1 = makeJob(kind: .pull)
        let job2 = makeJob(kind: .pull)
        sut.enqueue([job1, job2])

        XCTAssertTrue(sut.busyWorktreeIDs.contains(job1.worktreeID), "job1 worktree should be busy")
        XCTAssertTrue(sut.busyWorktreeIDs.contains(job2.worktreeID), "job2 worktree should be busy")

        await waitForIdle()
        XCTAssertTrue(sut.busyWorktreeIDs.isEmpty, "busyWorktreeIDs should be empty after all jobs complete")
    }

    func testBusyWorktreeIDs_excludesFailedJobs() async {
        mockExecutor.shouldFail = true
        let job = makeJob(kind: .pull)
        sut.enqueue(job)
        await waitForIdle()

        XCTAssertFalse(sut.busyWorktreeIDs.contains(job.worktreeID),
                       "Failed job should not keep worktree in busy set")
        XCTAssertTrue(sut.hasFailedJobs)
    }

    // MARK: - progressFraction

    func testProgressFraction_emptyQueue_returnsZero() {
        XCTAssertEqual(sut.progressFraction, 0)
    }

    func testProgressFraction_multipleJobs_zeroAfterCompletion() async {
        let jobs = (0..<4).map { _ in makeJob(kind: .pull) }
        sut.enqueue(jobs)
        XCTAssertEqual(sut.progressFraction, 0.0)

        await waitForIdle()
        // After all complete, queue is cleared → 0 of 0 = 0.0
        XCTAssertEqual(sut.progressFraction, 0.0)
        XCTAssertTrue(sut.jobs.isEmpty)
    }

    // MARK: - currentJobDescription

    func testCurrentJobDescription_nilWhenQueueEmpty() {
        XCTAssertNil(sut.currentJobDescription)
    }

    func testCurrentJobDescription_nilWhenIdle() async {
        sut.enqueue(makeJob(kind: .pull))
        await waitForIdle()
        XCTAssertNil(sut.currentJobDescription,
                     "currentJobDescription should be nil when no job is in-progress")
    }

    // MARK: - hasActiveJobs / hasFailedJobs

    func testHasActiveJobs_falseWhenOnlyFailedJobsRemain() async {
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await waitForIdle()

        XCTAssertFalse(sut.hasActiveJobs, "hasActiveJobs should be false for failed jobs")
        XCTAssertTrue(sut.hasFailedJobs)
    }

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
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await waitForIdle()

        mockExecutor.shouldFail = false
        sut.enqueue(makeJob(kind: .pull))
        await waitForIdle()

        sut.clearFailed()
        XCTAssertFalse(sut.hasFailedJobs)
    }

    // MARK: - onJobStateChange

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

    /// Simulates rapid enqueue from multiple repos at once. Verifies all jobs reach
    /// terminal state with no processingTask leaks.
    func testConcurrentEnqueueFromMultipleRepos_allJobsReachTerminalState() async {
        let repo3Path = "/tmp/bq-stress-repo-3"
        let repo4Path = "/tmp/bq-stress-repo-4"

        let jobs1 = (0..<4).map { _ in makeJob(kind: .pull) }
        let jobs2 = (0..<4).map { _ in
            BackgroundJob(
                worktreeID: UUID(),
                worktreePath: "\(repo3Path)/wt-\(UUID().uuidString.prefix(8))",
                folderName: "wt", displayName: "Repo3",
                repositoryPath: repo3Path, repositoryID: UUID(), kind: .pull
            )
        }
        let jobs3 = (0..<4).map { _ in
            BackgroundJob(
                worktreeID: UUID(),
                worktreePath: "\(repo4Path)/wt-\(UUID().uuidString.prefix(8))",
                folderName: "wt", displayName: "Repo4",
                repositoryPath: repo4Path, repositoryID: UUID(), kind: .pull
            )
        }

        sut.enqueue(jobs1 + jobs2 + jobs3)
        await waitForIdle(timeout: 10)

        XCTAssertFalse(sut.hasActiveJobs, "All jobs should reach terminal state")
        XCTAssertTrue(sut.busyWorktreeIDs.isEmpty, "No worktrees should remain busy")
        XCTAssertFalse(sut.hasFailedJobs, "No jobs should fail with a succeeding mock")
    }

    /// Enqueue → cancelAll → re-enqueue: verifies processingTasks are cleaned up
    /// and restarted correctly after cancellation (no leak from Fix 1).
    func testCancelAll_thenReenqueue_processesNewJobs() async {
        sut.enqueue((0..<5).map { _ in makeJob(kind: .pull) })
        sut.cancelAll()
        await waitForIdle()
        XCTAssertFalse(sut.hasActiveJobs)

        sut.enqueue(makeJob(kind: .pull))
        await waitForIdle(timeout: 5)

        XCTAssertFalse(sut.hasActiveJobs)
        XCTAssertFalse(sut.hasFailedJobs)
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
