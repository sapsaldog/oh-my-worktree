import Combine
import Foundation
import SwiftUI

@MainActor
final class WorktreeListViewModel: ObservableObject {
    @Published var worktrees: [Worktree] = []
    // WARNING: Intentionally NOT @Published. Do NOT add @Published here.
    // No SwiftUI view reads this in body, so firing objectWillChange on changes
    // causes "Publishing changes from within view updates" warnings.
    // AppDelegate and other observers must use `selectedWorktreeSubject` instead
    // of Combine's `$selectedWorktree` publisher (which doesn't exist).
    var selectedWorktree: Worktree? {
        didSet {
            guard selectedWorktree?.id != oldValue?.id else { return }
            selectedWorktreeSubject.send(selectedWorktree)
        }
    }
    let selectedWorktreeSubject = PassthroughSubject<Worktree?, Never>()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pullRequests: [String: PullRequestInfo] = [:]
    @Published var isGitHubRepo = false

    // FR-032: Multi-select (native ⌘+click / ⇧+click via SwiftUI List)
    @Published var selectedWorktreeIDs: Set<UUID> = []

    // FR-031: BackgroundTaskQueue (exposed for views)
    let jobQueue: BackgroundTaskQueue

    // FR-031: Controls the Import from GitHub PR sheet
    @Published var isShowingImportPR = false

    // Delete confirmation triggers (set by hidden shortcut buttons, observed by WorktreeListView)
    enum PendingDelete: Equatable {
        case remove, forceRemove, quickRemove
    }
    @Published var pendingDelete: PendingDelete?

    private let worktreeManager: WorktreeManager
    // internal for WorktreeListViewModel+ExternalTools extension
    let toolLauncher: ExternalToolLauncher
    // internal for WorktreeListViewModel+ExternalTools and handleJobStateChange
    let store: RepositoryStore
    private let fileCopier: WorktreeFileCopier
    private let pullRequestService: PullRequestFetching
    private var loadTask: Task<Void, Never>?
    private var prFetchTask: Task<Void, Never>?
    private var lastLoadTime: Date?
    private var queueCancellable: AnyCancellable?
    private var selectionSyncCancellable: AnyCancellable?
    private static let debounceInterval: TimeInterval = 2.0

    var repository: Repository? {
        didSet {
            if repository?.id != oldValue?.id {
                loadTask?.cancel()
                prFetchTask?.cancel()
                pullRequests = [:]
                isGitHubRepo = false
            }
        }
    }

    init(
        worktreeManager: WorktreeManager = WorktreeManager(),
        toolLauncher: ExternalToolLauncher = ExternalToolLauncher(),
        store: RepositoryStore = .shared,
        fileCopier: WorktreeFileCopier = WorktreeFileCopier(),
        pullRequestService: PullRequestFetching = PullRequestService()
    ) {
        self.worktreeManager = worktreeManager
        self.toolLauncher = toolLauncher
        self.store = store
        self.fileCopier = fileCopier
        self.pullRequestService = pullRequestService
        self.jobQueue = BackgroundTaskQueue(worktreeManager: worktreeManager, store: store)

        // Forward queue objectWillChange so views observing ViewModel also react to queue changes.
        // Use Task { @MainActor in } to break the synchronous Combine delivery chain.
        // A RunLoop- or DispatchQueue-based sink can fire during SwiftUI's rendering pass,
        // causing "Publishing changes from within view updates" warnings. Scheduling via
        // the MainActor cooperative queue guarantees delivery between rendering passes.
        // SwiftUI also naturally coalesces multiple objectWillChange signals per run loop,
        // so no explicit debounce is needed.
        queueCancellable = jobQueue.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            }

        // Keep selectedWorktree in sync with selectedWorktreeIDs.
        // The @Published sink fires synchronously during SwiftUI's event-processing
        // phase — after the binding setter stores the new value but before the
        // rendering pass begins. Setting selectedWorktree directly here is therefore
        // safe: objectWillChange.send() fires before any body evaluation, so SwiftUI
        // coalesces both notifications into one render with no "Publishing changes
        // from within view updates" warning.
        selectionSyncCancellable = $selectedWorktreeIDs
            .dropFirst()
            .sink { [weak self] ids in
                guard let self else { return }
                if ids.count == 1, let id = ids.first {
                    self.selectedWorktree = self.worktrees.first { $0.id == id }
                } else {
                    self.selectedWorktree = nil
                }
            }

        // Request notification permission early so the system prompt doesn't appear mid-task
        NotificationManager.shared.requestAuthorization()

        // React to job state changes
        jobQueue.onJobStateChange = { [weak self] job in
            self?.handleJobStateChange(job)
        }
    }

    private func handleJobStateChange(_ job: BackgroundJob) {
        switch (job.state, job.kind) {
        case (.completed, .removeWorktree), (.completed, .quickRemove):
            // Defer @Published writes to avoid "Publishing during view update" warnings.
            // The callback fires synchronously inside executeJob's Task continuation;
            // wrapping in a new Task guarantees the writes land between render passes.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.worktrees.removeAll { $0.id == job.worktreeID }
                if self.selectedWorktree?.id == job.worktreeID {
                    self.selectedWorktree = nil
                }
                self.selectedWorktreeIDs.remove(job.worktreeID)
                NotificationManager.shared.notifyCompleted(job: job)
            }
        case (.completed, .pull):
            Task { @MainActor [weak self] in
                await self?.loadWorktrees()
                NotificationManager.shared.notifyCompleted(job: job)
            }
        case (.completed, .addWorktreeFromPR):
            Task { @MainActor [weak self] in
                guard let self else { return }
                if await self.shouldCopyFiles(for: job.repositoryID) {
                    let copyResult = self.fileCopier.copyFiles(
                        from: job.repositoryPath, to: job.worktreePath
                    )
                    if !copyResult.errors.isEmpty {
                        self.errorMessage = "Some files could not be copied: "
                            + copyResult.errors.joined(separator: ", ")
                    }
                }
                await self.loadWorktrees()
                NotificationManager.shared.notifyCompleted(job: job)
            }
        case (.failed(let msg), _):
            Task { @MainActor [weak self] in
                self?.errorMessage = msg
                NotificationManager.shared.notifyFailed(message: msg, jobID: job.id)
            }
        default:
            break
        }
    }

    // MARK: - Load Worktrees

    func loadWorktrees(debounce: Bool = false) async {
        guard let repository else {
            worktrees = []
            return
        }

        if debounce, let last = lastLoadTime,
           Date().timeIntervalSince(last) < Self.debounceInterval {
            return
        }

        loadTask?.cancel()

        let task = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }

            self.isLoading = true
            defer { self.isLoading = false }

            do {
                var freshWorktrees = try await self.worktreeManager.listWorktrees(repositoryPath: repository.path)
                guard !Task.isCancelled else { return }
                let metadata = await self.store.getWorktreeMetadata(repositoryID: repository.id)

                freshWorktrees = await self.enriched(freshWorktrees, metadata: metadata)

                guard !Task.isCancelled else { return }

                freshWorktrees.sort { a, b in
                    (a.lastActivityAt ?? .distantPast) > (b.lastActivityAt ?? .distantPast)
                }

                self.worktrees = freshWorktrees
                self.lastLoadTime = Date()
                self.updateSelectedWorktree(from: freshWorktrees)
                self.schedulePRFetch(repositoryPath: repository.path)
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.worktrees = []
                }
            }
        }
        loadTask = task
        await task.value
    }

    // MARK: - Load Helpers

    private func enriched(_ worktrees: [Worktree], metadata: [WorktreeMetadata]) async -> [Worktree] {
        var result = worktrees

        // Step 1: Apply metadata (in-memory, no I/O)
        for i in result.indices {
            let meta = metadata.first(where: { $0.folderName == result[i].folderName })
            result[i].customName = meta?.customName
            result[i].prRemoteBranch = meta?.prRemoteBranch
        }

        // Step 2: Fetch commit dates concurrently (issue #12)
        let manager = worktreeManager
        await withTaskGroup(of: (Int, Date?).self) { group in
            for i in result.indices {
                let path = result[i].path
                group.addTask {
                    let date = await manager.lastCommitDate(worktreePath: path)
                    return (i, date)
                }
            }
            for await (index, commitDate) in group {
                let metaActivity = metadata.first(where: { $0.folderName == result[index].folderName })?.lastActivityAt
                switch (metaActivity, commitDate) {
                case let (date1?, date2?): result[index].lastActivityAt = max(date1, date2)
                case let (date1?, nil):    result[index].lastActivityAt = date1
                case let (nil, date2?):    result[index].lastActivityAt = date2
                case (nil, nil):           break
                }
            }
        }

        return result
    }

    private func updateSelectedWorktree(from worktrees: [Worktree]) {
        guard let selected = selectedWorktree else { return }
        selectedWorktree = worktrees.first(where: { $0.id == selected.id })
    }

    private func schedulePRFetch(repositoryPath: String) {
        let prService = pullRequestService
        prFetchTask?.cancel()
        prFetchTask = Task { @MainActor [weak self] in
            let available = await prService.isGitHubAvailable(repositoryPath: repositoryPath)
            guard !Task.isCancelled else { return }
            self?.isGitHubRepo = available

            guard available else { return }
            let prs = await prService.fetchPullRequests(repositoryPath: repositoryPath)
            guard !Task.isCancelled else { return }
            self?.pullRequests = prs
        }
    }

    // MARK: - Add Worktree

    func addWorktree(baseBranch: String? = nil) async {
        guard let repository else {
            errorMessage = OhMyWorktreeError.repositoryNotFound.errorDescription
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let existingNames = Set(worktrees.map { $0.folderName })
            let folderName = RandomNameGenerator.generate(existingFolderNames: existingNames)

            let newWorktree = try await worktreeManager.addWorktree(
                repositoryPath: repository.path,
                folderName: folderName,
                baseBranch: baseBranch
            )

            let metadata = WorktreeMetadata(folderName: folderName)
            await store.addWorktreeMetadata(metadata, repositoryID: repository.id)

            if await shouldCopyFiles(for: repository.id) {
                let copyResult = fileCopier.copyFiles(from: repository.path, to: newWorktree.path)
                if !copyResult.errors.isEmpty {
                    errorMessage = "Some files could not be copied: \(copyResult.errors.joined(separator: ", "))"
                }
            }

            await loadWorktrees()
            selectedWorktree = worktrees.first { $0.path == newWorktree.path }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add Worktree from PR (via queue)

    /// Enqueues a worktree-creation job for the given PR branch.
    /// If the branch is already checked out in another worktree, a versioned local
    /// branch name (e.g. `feature/foo-v2`) is generated so git can create a second
    /// worktree on the same remote ref. Returns an error string only when no
    /// repository is selected; otherwise always enqueues and returns nil.
    @discardableResult
    func addWorktreeFromPR(_ pr: PullRequestInfo) -> String? {
        guard let repository else {
            return OhMyWorktreeError.repositoryNotFound.errorDescription
        }

        // Include pending/in-progress import jobs for THIS repository so rapid
        // double-enqueue of the same PR doesn't collide on the same path/branch
        // before the list refreshes. Scoped by repositoryID to avoid cross-repo interference.
        let activeJobs = jobQueue.jobs.filter { $0.state.isActive && $0.repositoryID == repository.id }
        let queuedFolderNames = Set(activeJobs.map { $0.folderName })
        let queuedBranches = Set(activeJobs.compactMap { job -> String? in
            if case .addWorktreeFromPR(_, let local, _) = job.kind { return local }
            return nil
        })
        let existingFolderNames = Set(worktrees.map { $0.folderName }).union(queuedFolderNames)
        let existingBranches = Set(worktrees.compactMap { $0.branch }).union(queuedBranches)
        let isAlreadyCheckedOut = existingBranches.contains(pr.branch)

        // Always use a random folder name (same as regular addWorktree).
        let folderName = RandomNameGenerator.generate(existingFolderNames: existingFolderNames)

        let localBranch: String
        if isAlreadyCheckedOut {
            // The PR branch is already checked out: create a versioned local branch
            // (e.g. "feature/foo-v2") starting at origin/feature/foo.
            var version = 2
            while existingBranches.contains("\(pr.branch)-v\(version)") {
                version += 1
                if version > 100 {
                    return "Too many worktrees for branch '\(pr.branch)'"
                }
            }
            localBranch = "\(pr.branch)-v\(version)"
        } else {
            localBranch = pr.branch
        }

        let worktreePath = WorktreeManager.worktreePath(
            repositoryPath: repository.path, folderName: folderName
        )
        let job = BackgroundJob(
            worktreeID: Worktree.stableID(for: worktreePath),
            worktreePath: worktreePath,
            folderName: folderName,
            displayName: pr.branch,
            repositoryPath: repository.path,
            repositoryID: repository.id,
            kind: .addWorktreeFromPR(remoteBranch: pr.branch, localBranch: localBranch, prNumber: pr.number)
        )
        jobQueue.enqueue(job)
        return nil
    }

    // MARK: - Remove Worktree (via queue)

    func removeWorktree(_ worktree: Worktree, force: Bool = false) {
        guard let repository else { return }
        let job = BackgroundJob(
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            folderName: worktree.folderName,
            displayName: worktree.displayName,
            repositoryPath: repository.path,
            repositoryID: repository.id,
            kind: .removeWorktree(force: force)
        )
        jobQueue.enqueue(job)
    }

    func removeSelectedWorktrees(force: Bool = false) {
        guard let repository else { return }
        let targets = worktrees.filter { worktree in
            selectedWorktreeIDs.contains(worktree.id)
                && !worktree.isRoot(of: repository)
                && !worktree.isBare
                && !jobQueue.busyWorktreeIDs.contains(worktree.id)
        }
        let jobs = targets.map { worktree in
            BackgroundJob(
                worktreeID: worktree.id,
                worktreePath: worktree.path,
                folderName: worktree.folderName,
                displayName: worktree.displayName,
                repositoryPath: repository.path,
                repositoryID: repository.id,
                kind: .removeWorktree(force: force)
            )
        }
        jobQueue.enqueue(jobs)
        selectedWorktreeIDs = []
    }

    // MARK: - Git Pull

    func gitPull(_ worktree: Worktree) {
        guard let repository else { return }
        guard !jobQueue.busyWorktreeIDs.contains(worktree.id) else { return }
        let job = BackgroundJob(
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            folderName: worktree.folderName,
            displayName: worktree.displayName,
            repositoryPath: repository.path,
            repositoryID: repository.id,
            kind: .pull
        )
        jobQueue.enqueue(job)
    }

    // MARK: - Open Pull Request

    func openPullRequest(for worktree: Worktree) {
        let pr = worktree.branch.flatMap { pullRequests[$0] }
            ?? worktree.prRemoteBranch.flatMap { pullRequests[$0] }
        guard let pr else { return }
        NSWorkspace.shared.open(pr.url)
    }

    // MARK: - Rename Worktree

    func renameWorktree(_ worktree: Worktree, newName: String) async {
        guard let repository else { return }

        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        let customName: String? = trimmed.isEmpty ? nil : trimmed

        await store.updateCustomName(
            folderName: worktree.folderName,
            customName: customName,
            repositoryID: repository.id
        )

        if let index = worktrees.firstIndex(where: { $0.id == worktree.id }) {
            worktrees[index].customName = customName
        }
        if selectedWorktree?.id == worktree.id {
            selectedWorktree?.customName = customName
            // didSet only emits when the ID changes; bypass it so AppDelegate
            // updates the menu bar title immediately after a rename.
            selectedWorktreeSubject.send(selectedWorktree)
        }
    }

    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Private Helpers

    /// Returns whether env/file copying is enabled for the given repository,
    /// resolving the per-repo override against the global UserDefaults toggle.
    func shouldCopyFiles(for repositoryID: UUID) async -> Bool {
        let override = await store.getEnvCopyOverride(for: repositoryID)
        let globalDefault = UserDefaults.standard.object(forKey: "copyEnvFilesEnabled") as? Bool ?? true
        return override ?? globalDefault
    }
}
