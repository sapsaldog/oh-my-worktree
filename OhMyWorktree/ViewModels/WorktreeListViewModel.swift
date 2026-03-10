import Combine
import Foundation
import SwiftUI

@MainActor
final class WorktreeListViewModel: ObservableObject {
    @Published var worktrees: [Worktree] = []
    // Not @Published: no SwiftUI view reads this in body, so firing objectWillChange
    // when it changes would cause "Publishing changes from within view updates" warnings.
    // AppDelegate observes changes via selectedWorktreeSubject instead.
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

    // FR-032: Multi-select (native ⌘+click / ⇧+click via SwiftUI List)
    @Published var selectedWorktreeIDs: Set<UUID> = []

    // FR-031: BackgroundTaskQueue (exposed for views)
    let jobQueue: BackgroundTaskQueue

    // FR-031: Controls the Import from GitHub PR sheet
    @Published var isShowingImportPR = false

    private let worktreeManager: WorktreeManager
    private let toolLauncher: ExternalToolLauncher
    private let store: RepositoryStore
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
                prFetchTask?.cancel()
                pullRequests = [:]
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
            guard let self else { return }
            switch (job.state, job.kind) {
            case (.completed, .removeWorktree):
                // Immediately remove from the in-memory list
                self.worktrees.removeAll { $0.id == job.worktreeID }
                if self.selectedWorktree?.id == job.worktreeID {
                    self.selectedWorktree = nil
                }
                self.selectedWorktreeIDs.remove(job.worktreeID)
                NotificationManager.shared.notifyCompleted(job: job)
            case (.completed, .pull):
                Task { @MainActor [weak self] in await self?.loadWorktrees() }
                NotificationManager.shared.notifyCompleted(job: job)
            case (.completed, .addWorktreeFromPR):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let fileCopyOverride = await self.store.getEnvCopyOverride(for: job.repositoryID)
                    let globalDefault = UserDefaults.standard.object(forKey: "copyEnvFilesEnabled") as? Bool ?? true
                    if fileCopyOverride ?? globalDefault {
                        let copyResult = self.fileCopier.copyFiles(from: job.repositoryPath, to: job.worktreePath)
                        if !copyResult.errors.isEmpty {
                            self.errorMessage = "Some files could not be copied: \(copyResult.errors.joined(separator: ", "))"
                        }
                    }
                    await self.loadWorktrees()
                    self.isShowingImportPR = false
                }
                NotificationManager.shared.notifyCompleted(job: job)
            case (.failed(let msg), _):
                self.errorMessage = msg
                NotificationManager.shared.notifyFailed(message: msg, jobID: job.id)
            default:
                break
            }
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
        for i in result.indices {
            guard !Task.isCancelled else { return result }
            let wt = result[i]
            let meta = metadata.first(where: { $0.folderName == wt.folderName })
            result[i].customName = meta?.customName
            let metaActivity = meta?.lastActivityAt
            let commitDate = await worktreeManager.lastCommitDate(worktreePath: wt.path)
            switch (metaActivity, commitDate) {
            case let (date1?, date2?): result[i].lastActivityAt = max(date1, date2)
            case let (date1?, nil):    result[i].lastActivityAt = date1
            case let (nil, date2?):    result[i].lastActivityAt = date2
            case (nil, nil):           break
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

            let fileCopyOverride = await store.getEnvCopyOverride(for: repository.id)
            let globalDefault = UserDefaults.standard.object(forKey: "copyEnvFilesEnabled") as? Bool ?? true
            let shouldCopyFiles = fileCopyOverride ?? globalDefault
            if shouldCopyFiles {
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

        let baseName = pr.branch.replacingOccurrences(of: "/", with: "-")
        let existingFolderNames = Set(worktrees.map { $0.folderName })
        let existingBranches = Set(worktrees.compactMap { $0.branch })
        let isAlreadyCheckedOut = existingBranches.contains(pr.branch)

        let folderName: String
        let localBranch: String

        if isAlreadyCheckedOut {
            // The PR branch is already checked out: create a versioned local branch
            // (e.g. "feature/foo-v2") starting at origin/feature/foo.
            var version = 2
            while existingFolderNames.contains("\(baseName)-v\(version)")
                    || existingBranches.contains("\(pr.branch)-v\(version)") {
                version += 1
            }
            folderName = "\(baseName)-v\(version)"
            localBranch = "\(pr.branch)-v\(version)"
        } else {
            localBranch = pr.branch
            if existingFolderNames.contains(baseName) {
                var version = 2
                while existingFolderNames.contains("\(baseName)-v\(version)") { version += 1 }
                folderName = "\(baseName)-v\(version)"
            } else {
                folderName = baseName
            }
        }

        let repoName = (repository.path as NSString).lastPathComponent
        let worktreePath = (NSHomeDirectory() as NSString)
            .appendingPathComponent("oh-my-worktree/workspaces/\(repoName)/\(folderName)")
        let job = BackgroundJob(
            worktreeID: UUID(),
            worktreePath: worktreePath,
            folderName: folderName,
            displayName: pr.branch,
            repositoryPath: repository.path,
            repositoryID: repository.id,
            kind: .addWorktreeFromPR(remoteBranch: pr.branch, localBranch: localBranch)
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
        guard let branch = worktree.branch,
              let pr = pullRequests[branch]
        else { return }
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
        }
    }

    // MARK: - Open in External Tools

    func openInITerm(_ worktree: Worktree? = nil, mode: AppSettings.OpenMode = .newTab) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }
        do {
            try await toolLauncher.openInITerm(path: target.path, mode: mode)
            await recordActivity(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInGhostty(_ worktree: Worktree? = nil) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }
        do {
            try await toolLauncher.openInGhostty(path: target.path)
            await recordActivity(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInVSCode(_ worktree: Worktree? = nil, mode: AppSettings.OpenMode = .newWindow) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }
        do {
            try await toolLauncher.openInVSCode(path: target.path, mode: mode)
            await recordActivity(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInCursor(_ worktree: Worktree? = nil) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }
        do {
            try await toolLauncher.openInCursor(path: target.path)
            await recordActivity(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInCmux(_ worktree: Worktree? = nil) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }
        do {
            try await toolLauncher.openInCmux(path: target.path)
            await recordActivity(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recordActivity(for worktree: Worktree) async {
        guard let repository else { return }
        await store.updateLastActivity(folderName: worktree.folderName, repositoryID: repository.id)
        if let index = worktrees.firstIndex(where: { $0.id == worktree.id }) {
            worktrees[index].lastActivityAt = Date()
        }
    }

    // MARK: - Tool Availability

    var isITermAvailable: Bool { toolLauncher.isITermInstalled() }
    var isGhosttyAvailable: Bool { toolLauncher.isGhosttyInstalled() }
    var isVSCodeAvailable: Bool { toolLauncher.isVSCodeInstalled() }
    var isCursorAvailable: Bool { toolLauncher.isCursorInstalled() }
    var isCmuxAvailable: Bool { toolLauncher.isCmuxInstalled() }

    // MARK: - Context Menu Actions

    func contextMenuActions(for worktree: Worktree) -> ContextMenuActions {
        let isMultiSelected = selectedWorktreeIDs.count >= 2 && selectedWorktreeIDs.contains(worktree.id)

        if isMultiSelected {
            let anyNonRemovable = worktrees.contains { w in
                selectedWorktreeIDs.contains(w.id)
                    && ((repository.map { w.isRoot(of: $0) } ?? false) || w.isBare)
            }
            let hasRemovableTarget = !anyNonRemovable && worktrees.contains { w in
                selectedWorktreeIDs.contains(w.id)
                    && !jobQueue.busyWorktreeIDs.contains(w.id)
            }
            return ContextMenuActions(
                canOpen: false,
                canRename: false,
                canGitPull: false,
                canRemove: hasRemovableTarget,
                canForceRemove: hasRemovableTarget,
                canShowInFinder: false,
                canCopyPath: false
            )
        }

        // Single-item behavior
        let isBusy = jobQueue.busyWorktreeIDs.contains(worktree.id)
        let isRoot = repository.map { worktree.isRoot(of: $0) } ?? false
        let canRemove = !isRoot && !worktree.isBare && !isBusy
        return ContextMenuActions(
            canOpen: !isBusy,
            canRename: !isBusy,
            canGitPull: !worktree.isBare && !isBusy,
            canRemove: canRemove,
            canForceRemove: canRemove,
            canShowInFinder: true,
            canCopyPath: true
        )
    }

    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
    }
}

// MARK: - ContextMenuActions

struct ContextMenuActions: Equatable {
    let canOpen: Bool
    let canRename: Bool
    let canGitPull: Bool
    let canRemove: Bool
    let canForceRemove: Bool
    let canShowInFinder: Bool
    let canCopyPath: Bool
}
