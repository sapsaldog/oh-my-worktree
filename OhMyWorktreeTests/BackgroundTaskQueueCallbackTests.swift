import Foundation
import Testing

@testable import OhMyWorktree

// MARK: - BackgroundTaskQueue Callback & Stress Tests

@Suite(.serialized)
@MainActor
struct BackgroundTaskQueueCallbackTests {

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

    // MARK: - onJobStateChange

    @Test func onJobStateChange_completedCalledOnSuccess() async {
        let job = makeJob(kind: .pull)

        await confirmation { completed in
            sut.onJobStateChange = { changedJob in
                if changedJob.id == job.id && changedJob.state == .completed {
                    completed()
                }
            }
            sut.enqueue(job)
            await sut.waitUntilIdle()
        }
    }

    @Test func onJobStateChange_failedCalledOnGitError() async {
        mockExecutor.shouldFail = true
        let job = makeJob(kind: .pull)

        await confirmation { failed in
            sut.onJobStateChange = { changedJob in
                if changedJob.id == job.id, case .failed = changedJob.state {
                    failed()
                }
            }
            sut.enqueue(job)
            await sut.waitUntilIdle()
        }
    }

    @Test func onJobStateChange_receivesCorrectJobID() async {
        let jobs = (0..<3).map { _ in makeJob(kind: .pull) }
        let enqueuedIDs = Set(jobs.map { $0.id })

        await confirmation(expectedCount: 3) { received in
            var seen: Set<UUID> = []
            sut.onJobStateChange = { changedJob in
                if changedJob.state == .completed && enqueuedIDs.contains(changedJob.id) {
                    if seen.insert(changedJob.id).inserted {
                        received()
                    }
                }
            }
            sut.enqueue(jobs)
            await sut.waitUntilIdle()
        }
    }

    @Test func quickRemoveJob_callbackFiredOnCompletion() async {
        let job = makeJob(kind: .quickRemove)

        await confirmation { completed in
            sut.onJobStateChange = { changedJob in
                if changedJob.id == job.id && changedJob.state == .completed {
                    completed()
                }
            }
            sut.enqueue(job)
            await sut.waitUntilIdle()
        }
    }

    // MARK: - Stress Tests

    @Test func rapidEnqueueAndCancelAll_allReachTerminalState() async {
        let jobs = (0..<20).map { _ in makeJob(kind: .pull) }
        sut.enqueue(jobs)
        sut.cancelPending()
        await sut.waitUntilIdle()

        let pendingCount = sut.jobs.filter { $0.state == .pending }.count
        #expect(pendingCount == 0, "No jobs should remain pending after cancelPending")
        #expect(false == sut.hasActiveJobs)
    }

    @Test func rapidEnqueueMultipleRepos_eachProcessedIndependently() async {
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
        await sut.waitUntilIdle()

        #expect(false == sut.hasActiveJobs)
        #expect(sut.busyWorktreeIDs.isEmpty)
    }

    @Test func repeatedEnqueueAfterIdle_cleansUpCorrectly() async {
        for _ in 0..<5 {
            sut.enqueue(makeJob(kind: .pull))
            await sut.waitUntilIdle()
            #expect(false == sut.hasActiveJobs)
            #expect(sut.busyWorktreeIDs.isEmpty)
        }
        #expect(sut.jobs.isEmpty)
    }

    @Test func concurrentEnqueueFromMultipleRepos_allJobsReachTerminalState() async {
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
        await sut.waitUntilIdle()

        #expect(false == sut.hasActiveJobs, "All jobs should reach terminal state")
        #expect(sut.busyWorktreeIDs.isEmpty, "No worktrees should remain busy")
        #expect(false == sut.hasFailedJobs, "No jobs should fail with a succeeding mock")
    }

    @Test func cancelAll_thenReenqueue_processesNewJobs() async {
        sut.enqueue((0..<5).map { _ in makeJob(kind: .pull) })
        sut.cancelPending()
        await sut.waitUntilIdle()
        #expect(false == sut.hasActiveJobs)

        sut.enqueue(makeJob(kind: .pull))
        await sut.waitUntilIdle()

        #expect(false == sut.hasActiveJobs)
        #expect(false == sut.hasFailedJobs)
    }
}
