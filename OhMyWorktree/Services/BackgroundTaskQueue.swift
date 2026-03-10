import Foundation

@MainActor
final class BackgroundTaskQueue: ObservableObject {
    @Published private(set) var jobs: [BackgroundJob] = []

    /// Called whenever a job transitions to completed/failed/cancelled.
    var onJobStateChange: (@MainActor (BackgroundJob) -> Void)?

    private let worktreeManager: WorktreeManager
    private let store: RepositoryStore
    /// Serial processing task per repository path (prevents git lock conflicts).
    private var processingTasks: [String: Task<Void, Never>] = [:]

    /// Maximum duration (in seconds) for any single job before it times out.
    /// Injectable for testing — defaults to 60 seconds in production.
    let jobTimeoutSeconds: TimeInterval

    init(worktreeManager: WorktreeManager, store: RepositoryStore, jobTimeoutSeconds: TimeInterval = 60) {
        self.worktreeManager = worktreeManager
        self.store = store
        self.jobTimeoutSeconds = jobTimeoutSeconds
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

    /// Cancels all pending jobs. In-progress jobs continue to completion.
    /// Use `cancel(_:)` to cancel individual jobs by ID.
    func cancelPending() {
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
    var hasFailedJobs: Bool { failedJobCount > 0 }
    var failedJobCount: Int { jobs.filter { if case .failed = $0.state { return true }; return false }.count }

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
        case .addWorktreeFromPR: return "Importing \(job.displayName)..."
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
        // Note: O(n²) — each iteration scans the full array. Consider an indexed
        // lookup if bulk enqueue (>100 jobs) becomes a real use case.
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
        let timeout = jobTimeoutSeconds

        do {
            // Wrap the git operation in a timeout to prevent indefinite blocking
            // if a git process hangs (e.g. waiting for SSH passphrase or network).
            try await withJobTimeout(seconds: timeout) {
                switch job.kind {
                case .removeWorktree(let force):
                    if FileManager.default.fileExists(atPath: job.worktreePath) {
                        try await wm.removeWorktree(
                            repositoryPath: job.repositoryPath,
                            worktreePath: job.worktreePath,
                            force: force
                        )
                    } else {
                        // Directory was manually deleted; prune the dangling git
                        // registration so it doesn't reappear on next reload.
                        // Ignore prune errors — metadata cleanup below is sufficient.
                        try? await wm.pruneWorktrees(repositoryPath: job.repositoryPath)
                    }
                    await st.removeWorktreeMetadata(
                        folderName: job.folderName,
                        repositoryID: job.repositoryID
                    )
                case .pull:
                    _ = try await wm.gitPull(worktreePath: job.worktreePath)
                case .addWorktreeFromPR(let remoteBranch, let localBranch):
                    try await wm.fetchBranch(remoteBranch, repositoryPath: job.repositoryPath)
                    // Always create from origin/<remoteBranch> using -B so that:
                    // 1. Stale local branches are reset to the remote HEAD
                    // 2. Leftover local branches (e.g. feature/foo-v2) don't cause "already exists" errors
                    _ = try await wm.addWorktreeFromRemoteBranch(
                        repositoryPath: job.repositoryPath,
                        folderName: job.folderName,
                        localBranch: localBranch,
                        remoteBranch: remoteBranch
                    )
                    let metadata = WorktreeMetadata(folderName: job.folderName, prRemoteBranch: remoteBranch)
                    await st.addWorktreeMetadata(metadata, repositoryID: job.repositoryID)
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

    /// Executes `operation` with the given timeout. Throws `BackgroundJobTimeoutError` if exceeded.
    /// The method is nonisolated so git work runs off the MainActor without blocking the UI.
    private nonisolated func withJobTimeout(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        precondition(seconds > 0, "Job timeout must be positive")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw BackgroundJobTimeoutError(seconds: Int(seconds))
            }
            // Take the first result (success or the first thrown error) then cancel the other task.
            do {
                _ = try await group.next()
                group.cancelAll()
                // Drain the cancelled task so its CancellationError is not
                // implicitly rethrown when the task group scope exits.
                while !group.isEmpty {
                    _ = try? await group.next()
                }
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    // MARK: - Private: Idle Cleanup

    private static let maxFailedJobs = 50
    /// Discard failed jobs older than this interval during idle cleanup.
    private static let failedJobMaxAge: TimeInterval = 3600 // 1 hour

    private func clearJobsIfIdle() {
        guard activeJobs.isEmpty else { return }
        // Fast-path: nothing failed, clear everything.
        if failedJobCount == 0 {
            if !jobs.isEmpty {
                jobs = []
                refreshBusyWorktreeIDs()
            }
            return
        }
        // Keep only the most recent failed jobs for display, evicting stale entries.
        let cutoff = Date().addingTimeInterval(-Self.failedJobMaxAge)
        let failed = jobs
            .filter { if case .failed = $0.state { return true }; return false }
            .filter { $0.enqueuedAt > cutoff }
        jobs = Array(failed.suffix(Self.maxFailedJobs))
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

/// Thrown when a background job exceeds the configured timeout.
struct BackgroundJobTimeoutError: LocalizedError {
    let seconds: Int
    var errorDescription: String? {
        "Operation timed out after \(seconds) seconds"
    }
}
