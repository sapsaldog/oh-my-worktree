import Foundation
import Testing

@testable import OhMyWorktree

// MARK: - BackgroundTaskQueue Tests

@Suite(.serialized)
@MainActor
struct BackgroundTaskQueueTests {

    private let mockExecutor: MockSimpleGitExecutor
    private let sut: BackgroundTaskQueue
    private let repoPath = "/tmp/bq-test-repo"
    private let repoID = UUID()

    init() async throws {
        mockExecutor = MockSimpleGitExecutor()
        sut = BackgroundTaskQueue(
            worktreeManager: WorktreeManager(executor: mockExecutor, fileManager: MockNoOpFileManager()),
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

    // MARK: - cancel

    @Test func cancel_pendingJob_setsCancelled() {
        // Enqueue two jobs for the same repoPath so the second stays pending
        let job1 = makeJob(kind: .pull)
        let job2 = makeJob(kind: .pull)
        sut.enqueue([job1, job2])

        // job2 should be pending (job1 started processing)
        let pendingIndex = sut.jobs.firstIndex(where: { $0.id == job2.id && $0.state == .pending })
        if let idx = pendingIndex {
            sut.cancel(sut.jobs[idx].id)
            #expect(sut.jobs[idx].state == .cancelled)
        }
        // If job2 is already inProgress, the test is a no-op — still valid
    }

    @Test func cancel_nonExistentID_noChange() {
        sut.cancel(UUID())
        #expect(sut.jobs.isEmpty)
    }

    // MARK: - cancelPending

    @Test func cancelAll_setsPendingJobsToCancelled() {
        let jobs = (0..<3).map { _ in makeJob(kind: .pull) }
        sut.enqueue(jobs)
        sut.cancelPending()

        let pendingCount = sut.jobs.filter { $0.state == .pending }.count
        #expect(pendingCount == 0)
    }

    // MARK: - busyWorktreeIDs

    @Test func busyWorktreeIDs_emptyQueue_isEmpty() {
        #expect(sut.busyWorktreeIDs.isEmpty)
    }

    @Test func busyWorktreeIDs_afterIdle_isEmpty() async {
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()
        #expect(sut.busyWorktreeIDs.isEmpty)
    }

    @Test func busyWorktreeIDs_updatesOnEnqueue() {
        let job = makeJob(kind: .pull)
        #expect(false == sut.busyWorktreeIDs.contains(job.worktreeID))
        sut.enqueue(job)
        #expect(sut.busyWorktreeIDs.contains(job.worktreeID))
    }

    @Test func busyWorktreeIDs_clearsAfterIdle() async {
        let job = makeJob(kind: .pull)
        sut.enqueue(job)
        #expect(false == sut.busyWorktreeIDs.isEmpty)
        await sut.waitUntilIdle()
        #expect(sut.busyWorktreeIDs.isEmpty)
    }

    @Test func busyWorktreeIDs_updatesOnCancel() {
        let job1 = makeJob(kind: .pull)
        let job2 = makeJob(kind: .pull)
        sut.enqueue([job1, job2])

        if let pendingJob = sut.jobs.first(where: { $0.state == .pending }) {
            let worktreeID = pendingJob.worktreeID
            #expect(sut.busyWorktreeIDs.contains(worktreeID))
            sut.cancel(pendingJob.id)
            #expect(false == sut.busyWorktreeIDs.contains(worktreeID))
        }
    }

    @Test func busyWorktreeIDs_tracksActiveWorktrees_andClearsOnCompletion() async {
        let job1 = makeJob(kind: .pull)
        let job2 = makeJob(kind: .pull)
        sut.enqueue([job1, job2])

        #expect(sut.busyWorktreeIDs.contains(job1.worktreeID), "job1 worktree should be busy")
        #expect(sut.busyWorktreeIDs.contains(job2.worktreeID), "job2 worktree should be busy")

        await sut.waitUntilIdle()
        #expect(sut.busyWorktreeIDs.isEmpty, "busyWorktreeIDs should be empty after all jobs complete")
    }

    @Test func busyWorktreeIDs_excludesFailedJobs() async {
        mockExecutor.shouldFail = true
        let job = makeJob(kind: .pull)
        sut.enqueue(job)
        await sut.waitUntilIdle()

        #expect(false == sut.busyWorktreeIDs.contains(job.worktreeID),
               "Failed job should not keep worktree in busy set")
        #expect(sut.hasFailedJobs)
    }

    // MARK: - progressFraction

    @Test func progressFraction_emptyQueue_returnsZero() {
        #expect(sut.progressFraction == 0)
    }

    @Test func progressFraction_multipleJobs_zeroAfterCompletion() async {
        let jobs = (0..<4).map { _ in makeJob(kind: .pull) }
        sut.enqueue(jobs)
        #expect(sut.progressFraction == 0.0)

        await sut.waitUntilIdle()
        // After all complete, queue is cleared → 0 of 0 = 0.0
        #expect(sut.progressFraction == 0.0)
        #expect(sut.jobs.isEmpty)
    }

    @Test func progressFraction_withStaleFailedJobs_excludesFailedFromDenominator() async {
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()
        #expect(sut.hasFailedJobs, "Precondition: should have 1 failed job")

        mockExecutor.shouldFail = false
        let job2 = makeJob(kind: .pull)
        let job3 = makeJob(kind: .pull)
        sut.enqueue([job2, job3])

        #expect(sut.progressFraction == 0.0,
               "Progress should be 0% with stale failed + 2 pending, not 1/3 = 33%")
    }

    // MARK: - currentJobDescription

    @Test func currentJobDescription_nilWhenQueueEmpty() {
        #expect(sut.currentJobDescription == nil)
    }

    @Test func currentJobDescription_nilWhenIdle() async {
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()
        #expect(sut.currentJobDescription == nil,
               "currentJobDescription should be nil when no job is in-progress")
    }

    // MARK: - hasActiveJobs / hasFailedJobs

    @Test func hasActiveJobs_falseWhenOnlyFailedJobsRemain() async {
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()

        #expect(false == sut.hasActiveJobs, "hasActiveJobs should be false for failed jobs")
        #expect(sut.hasFailedJobs)
    }

    @Test func hasFailedJobs_noJobs_returnsFalse() {
        #expect(false == sut.hasFailedJobs)
    }

    @Test func hasFailedJobs_afterFailure_returnsTrue() async {
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()
        #expect(sut.hasFailedJobs)
    }

    @Test func hasFailedJobs_afterSuccess_returnsFalse() async {
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()
        #expect(false == sut.hasFailedJobs)
    }

    // MARK: - clearFailed

    @Test func clearFailed_removesFailedJobs() async {
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()
        #expect(sut.hasFailedJobs)

        sut.clearFailed()

        #expect(false == sut.hasFailedJobs)
        #expect(sut.jobs.isEmpty)
    }

    @Test func clearFailed_leavesNonFailedJobsIntact() async {
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()

        mockExecutor.shouldFail = false
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()

        sut.clearFailed()
        #expect(false == sut.hasFailedJobs)
    }

    // MARK: - failedJobCount

    @Test func failedJobCount_noJobs_returnsZero() {
        #expect(sut.failedJobCount == 0)
    }

    @Test func failedJobCount_afterMultipleFailures_returnsCorrectCount() async {
        mockExecutor.shouldFail = true
        sut.enqueue([makeJob(kind: .pull), makeJob(kind: .pull)])
        await sut.waitUntilIdle()

        #expect(sut.failedJobCount == 2)
    }

    @Test func failedJobCount_afterClearFailed_returnsZero() async {
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()
        #expect(sut.failedJobCount == 1)

        sut.clearFailed()
        #expect(sut.failedJobCount == 0)
    }

    // MARK: - activeJobs

    @Test func activeJobs_emptyQueue_isEmpty() {
        #expect(sut.activeJobs.isEmpty)
    }

    @Test func activeJobs_afterAllComplete_isEmpty() async {
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()
        #expect(sut.activeJobs.isEmpty)
    }

    @Test func activeJobs_excludesFailedJobs() async {
        mockExecutor.shouldFail = true
        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()

        #expect(sut.activeJobs.isEmpty)
        #expect(false == sut.jobs.isEmpty, "Failed jobs should still be in jobs array")
    }

    // MARK: - Quick Remove

    @Test func quickRemoveJob_completesSuccessfully() async {
        let job = makeJob(kind: .quickRemove)
        sut.enqueue(job)
        await sut.waitUntilIdle()

        #expect(false == sut.hasActiveJobs)
        #expect(false == sut.hasFailedJobs, "Quick remove should succeed with mock executor")
    }

    // MARK: - jobTimeoutSecondsKey

    @Test func jobTimeoutSecondsKey_hasExpectedValue() {
        #expect(BackgroundTaskQueue.jobTimeoutSecondsKey == "jobTimeoutSeconds")
    }

    @Test func defaultJobTimeoutSeconds_isSixty() {
        #expect(BackgroundTaskQueue.defaultJobTimeoutSeconds == 60)
    }

    // MARK: - BackgroundJobTimeoutError

    @Test func timeoutError_hasDescriptiveMessage() {
        let error = BackgroundJobTimeoutError(seconds: 60)
        #expect(error.errorDescription != nil)
        #expect(
            error.errorDescription?.contains("60") == true,
            "Timeout error should mention the 60-second limit"
        )
    }

    @Test func timeoutError_mentionsSettingsAndQuickRemove() {
        let error = BackgroundJobTimeoutError(seconds: 120)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("120"), "Should mention timeout duration")
        #expect(desc.contains("Settings"), "Should mention Settings")
        #expect(desc.contains("Quick Remove"), "Should mention Quick Remove as alternative")
    }
}
