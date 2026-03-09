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
        guard let index = jobs.firstIndex(where: { $0.id == jobID }),
              case .pending = jobs[index].state else { return }
        jobs[index].state = .cancelled
        refreshBusyWorktreeIDs()
        onJobStateChange?(jobs[index])
    }

    func cancelAll() {
        for i in jobs.indices where jobs[i].state == .pending {
            jobs[i].state = .cancelled
            onJobStateChange?(jobs[i])
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
        processingTasks[repoPath] = Task { [weak self] in
            await self?.processQueue(for: repoPath)
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
        jobs[index].state = .inProgress
        refreshBusyWorktreeIDs()

        do {
            let job = jobs[index]
            switch job.kind {
            case .removeWorktree(let force):
                try await worktreeManager.removeWorktree(
                    repositoryPath: job.repositoryPath,
                    worktreePath: job.worktreePath,
                    force: force
                )
                await store.removeWorktreeMetadata(
                    folderName: job.folderName,
                    repositoryID: job.repositoryID
                )
            case .pull:
                _ = try await worktreeManager.gitPull(worktreePath: job.worktreePath)
            }
            if let i = jobs.firstIndex(where: { $0.id == jobID }) {
                jobs[i].state = .completed
                refreshBusyWorktreeIDs()
                onJobStateChange?(jobs[i])
            }
        } catch {
            if let i = jobs.firstIndex(where: { $0.id == jobID }) {
                let job = jobs[i]
                jobs[i].state = .failed("'\(job.displayName)' \(job.kind.failureMessage): \(error.localizedDescription)")
                refreshBusyWorktreeIDs()
                onJobStateChange?(jobs[i])
            }
        }
    }

    private static let maxFailedJobs = 50

    private func clearJobsIfIdle() {
        guard activeJobs.isEmpty else { return }
        // Keep failed jobs visible until the user dismisses them
        jobs = jobs.filter { if case .failed = $0.state { return true }; return false }
        // Auto-prune oldest failed jobs if over limit
        if jobs.count > Self.maxFailedJobs {
            jobs = Array(jobs.suffix(Self.maxFailedJobs))
        }
        refreshBusyWorktreeIDs()
    }

    private func refreshBusyWorktreeIDs() {
        busyWorktreeIDs = Set(jobs.filter { $0.state.isActive }.map { $0.worktreeID })
    }
}
