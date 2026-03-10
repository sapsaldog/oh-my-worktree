import Foundation

@MainActor
final class BackgroundTaskQueue: ObservableObject {
    @Published private(set) var jobs: [BackgroundJob] = []

    /// Called whenever a job transitions to completed/failed/cancelled.
    var onJobStateChange: ((BackgroundJob) -> Void)?

    private let worktreeManager: WorktreeManager
    private let store: RepositoryStore
    /// Serial processing task per repository path (prevents git lock conflicts).
    private var processingTasks: [String: Task<Void, Never>] = [:]

    /// Maximum duration (in seconds) for any single job before it times out.
    static let jobTimeoutSeconds: TimeInterval = 60

    init(worktreeManager: WorktreeManager, store: RepositoryStore) {
        self.worktreeManager = worktreeManager
        self.store = store
    }

    // MARK: - Public Interface

    func enqueue(_ job: BackgroundJob) {
        jobs.append(job)
        refreshBusyWorktreeIDs()
        startProcessingIfNeeded(for: job.repositoryPath)
    }

    func enqueue(_ newJobs: [BackgroundJob]) {
        guard !newJobs.isEmpty else { return }
        jobs.append(contentsOf: newJobs)
        refreshBusyWorktreeIDs()
        Set(newJobs.map { $0.repositoryPath }).forEach { startProcessingIfNeeded(for: $0) }
    }

    func cancel(_ jobID: UUID) {
        guard let index = jobIndex(for: jobID),
              case .pending = jobs[index].state else { return }
        jobs[index].state = .cancelled
        refreshBusyWorktreeIDs()
        let snapshot = jobs[index]
        onJobStateChange?(snapshot)
    }

    func cancelAll() {
        for i in jobs.indices where jobs[i].state == .pending {
            jobs[i].state = .cancelled
            let snapshot = jobs[i]
            onJobStateChange?(snapshot)
        }
        refreshBusyWorktreeIDs()
    }

    // MARK: - Derived State

    var activeJobs: [BackgroundJob] { jobs.filter { $0.state.isActive } }
    var hasActiveJobs: Bool { !activeJobs.isEmpty }
    @Published private(set) var busyWorktreeIDs: Set<UUID> = []
    var hasFailedJobs: Bool { jobs.contains { if case .failed = $0.state { return true }; return false } }

    func clearFailed() {
        jobs = jobs.filter { if case .failed = $0.state { return false }; return true }
        refreshBusyWorktreeIDs()
    }

    var progressFraction: Double {
        guard !jobs.isEmpty else { return 0 }
        let done = jobs.filter { $0.state.isTerminal }.count
        return Double(done) / Double(jobs.count)
    }

    var currentJobDescription: String? {
        guard let job = jobs.first(where: { $0.state == .inProgress }) else { return nil }
        switch job.kind {
        case .removeWorktree: return "Removing \(job.displayName)..."
        case .pull: return "Pulling \(job.displayName)..."
        }
    }

    // MARK: - Private: Queue Processing

    private func startProcessingIfNeeded(for repoPath: String) {
        guard processingTasks[repoPath] == nil else { return }
        // Fix 1: guard let self prevents processingTasks from leaking if self is deallocated
        // before the task runs, which would leave the entry non-nil and block future jobs.
        processingTasks[repoPath] = Task { [weak self] in
            guard let self else { return }
            await self.processQueue(for: repoPath)
        }
    }

    private func processQueue(for repoPath: String) async {
        defer {
            processingTasks[repoPath] = nil
            clearJobsIfIdle()
        }
        while let index = jobs.firstIndex(where: { $0.repositoryPath == repoPath && $0.state == .pending }) {
            await executeJob(at: index)
        }
    }

    private func executeJob(at index: Int) async {
        let jobID = jobs[index].id
        // Capture a value-type snapshot of the job before marking inProgress
        // so the switch below uses stable state even if the array is mutated.
        let job = jobs[index]
        jobs[index].state = .inProgress
        refreshBusyWorktreeIDs()

        // Capture service references as local constants so the @Sendable closure
        // below doesn't need to re-cross the MainActor boundary.
        let wm = worktreeManager
        let st = store

        do {
            // Fix 3: Wrap the git operation in a timeout to prevent indefinite blocking
            // if a git process hangs (e.g. waiting for SSH passphrase or network).
            try await withJobTimeout {
                switch job.kind {
                case .removeWorktree(let force):
                    // Fix 4: Silently succeed if the worktree was already manually deleted;
                    // still clean up metadata so the app stays consistent.
                    if FileManager.default.fileExists(atPath: job.worktreePath) {
                        try await wm.removeWorktree(
                            repositoryPath: job.repositoryPath,
                            worktreePath: job.worktreePath,
                            force: force
                        )
                    }
                    await st.removeWorktreeMetadata(
                        folderName: job.folderName,
                        repositoryID: job.repositoryID
                    )
                case .pull:
                    _ = try await wm.gitPull(worktreePath: job.worktreePath)
                }
            }
            // Fix 2: Re-look up by ID (not original index) and capture an explicit
            // value-copy snapshot before invoking the callback, making it clear that
            // the callback receives stable, point-in-time state.
            if let i = jobIndex(for: jobID) {
                jobs[i].state = .completed
                refreshBusyWorktreeIDs()
                let snapshot = jobs[i]
                onJobStateChange?(snapshot)
            }
        } catch {
            if let i = jobIndex(for: jobID) {
                jobs[i].state = .failed("'\(job.displayName)' \(job.kind.failureMessage): \(error.localizedDescription)")
                refreshBusyWorktreeIDs()
                let snapshot = jobs[i]
                onJobStateChange?(snapshot)
            }
        }
    }

    // MARK: - Private: Timeout

    /// Executes `operation` with a fixed timeout. Throws `BackgroundJobTimeoutError` if exceeded.
    /// The method is nonisolated so git work runs off the MainActor without blocking the UI.
    private nonisolated func withJobTimeout(
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(BackgroundTaskQueue.jobTimeoutSeconds * 1_000_000_000))
                throw BackgroundJobTimeoutError()
            }
            // Take the first result (success or the first thrown error) then cancel the other task.
            do {
                _ = try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    // MARK: - Private: Idle Cleanup

    private static let maxFailedJobs = 50

    private func clearJobsIfIdle() {
        guard activeJobs.isEmpty else { return }
        let failedJobs = jobs.filter { if case .failed = $0.state { return true }; return false }
        // Fast-path: nothing failed, clear everything.
        if failedJobs.isEmpty {
            if !jobs.isEmpty {
                jobs = []
                refreshBusyWorktreeIDs()
            }
            return
        }
        // Keep only the most recent failed jobs for display.
        jobs = Array(failedJobs.suffix(Self.maxFailedJobs))
        refreshBusyWorktreeIDs()
    }

    // MARK: - Private: Helpers

    /// Fix 9: Centralized job ID → index lookup. All O(n) searches go through here,
    /// making it easy to swap in an O(1) implementation later if needed.
    private func jobIndex(for id: UUID) -> Int? {
        jobs.firstIndex(where: { $0.id == id })
    }

    private func refreshBusyWorktreeIDs() {
        busyWorktreeIDs = Set(jobs.filter { $0.state.isActive }.map { $0.worktreeID })
    }
}

// MARK: - BackgroundJobTimeoutError

/// Thrown when a background job exceeds `BackgroundTaskQueue.jobTimeoutSeconds`.
struct BackgroundJobTimeoutError: LocalizedError {
    var errorDescription: String? {
        "Operation timed out after \(Int(BackgroundTaskQueue.jobTimeoutSeconds)) seconds"
    }
}
