import Foundation
import SwiftUI

@MainActor
final class WorktreeListViewModel: ObservableObject {
    @Published var worktrees: [Worktree] = []
    @Published var selectedWorktree: Worktree?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pullResultMessage: String?
    @Published var pullingWorktrees: Set<UUID> = []
    @Published var pullRequests: [String: PullRequestInfo] = [:]
    private let worktreeManager: WorktreeManager
    private let toolLauncher: ExternalToolLauncher
    private let store: RepositoryStore
    private let fileCopier: WorktreeFileCopier
    private let pullRequestService: PullRequestFetching
    private var loadTask: Task<Void, Never>?
    private var prFetchTask: Task<Void, Never>?
    private var lastLoadTime: Date?
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
    }

    // MARK: - Load Worktrees

    func loadWorktrees(debounce: Bool = false) async {
        guard let repository else {
            worktrees = []
            return
        }

        // Skip if recently loaded (debounce for automatic refresh triggers)
        if debounce, let last = lastLoadTime,
           Date().timeIntervalSince(last) < Self.debounceInterval {
            return
        }

        // Cancel any in-flight load to avoid race conditions
        loadTask?.cancel()

        let task = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }

            self.isLoading = true
            defer { self.isLoading = false }

            do {
                // Always fetch fresh from git
                var freshWorktrees = try await self.worktreeManager.listWorktrees(repositoryPath: repository.path)
                guard !Task.isCancelled else { return }
                let metadata = await self.store.getWorktreeMetadata(repositoryID: repository.id)

                // Enrich worktrees with metadata (customName, last activity time)
                for i in freshWorktrees.indices {
                    guard !Task.isCancelled else { return }
                    let wt = freshWorktrees[i]
                    let meta = metadata.first(where: { $0.folderName == wt.folderName })
                    freshWorktrees[i].customName = meta?.customName
                    let metaActivity = meta?.lastActivityAt
                    let commitDate = await self.worktreeManager.lastCommitDate(worktreePath: wt.path)

                    // Use the most recent of metadata activity and last commit
                    switch (metaActivity, commitDate) {
                    case let (a?, c?):
                        freshWorktrees[i].lastActivityAt = max(a, c)
                    case let (a?, nil):
                        freshWorktrees[i].lastActivityAt = a
                    case let (nil, c?):
                        freshWorktrees[i].lastActivityAt = c
                    case (nil, nil):
                        break
                    }
                }

                guard !Task.isCancelled else { return }

                // Sort by last activity (most recent first)
                freshWorktrees.sort { a, b in
                    (a.lastActivityAt ?? .distantPast) > (b.lastActivityAt ?? .distantPast)
                }

                self.worktrees = freshWorktrees
                self.lastLoadTime = Date()

                // Update selected worktree with fresh data, or reset if gone
                if let selected = self.selectedWorktree {
                    if let updated = self.worktrees.first(where: { $0.path == selected.path }) {
                        self.selectedWorktree = updated
                    } else {
                        self.selectedWorktree = nil
                    }
                }

                // Fetch PR info in a non-blocking side task
                let repoPath = repository.path
                let prService = self.pullRequestService
                self.prFetchTask?.cancel()
                self.prFetchTask = Task { @MainActor [weak self] in
                    let prs = await prService.fetchPullRequests(repositoryPath: repoPath)
                    guard !Task.isCancelled else { return }
                    self?.pullRequests = prs
                }
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

    // MARK: - Add Worktree

    func addWorktree(baseBranch: String? = nil) async {
        guard let repository else {
            errorMessage = OhMyWorktreeError.repositoryNotFound.errorDescription
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Generate a unique folder name
            let existingNames = Set(worktrees.map { $0.folderName })
            let folderName = RandomNameGenerator.generate(existingFolderNames: existingNames)

            let newWorktree = try await worktreeManager.addWorktree(
                repositoryPath: repository.path,
                folderName: folderName,
                baseBranch: baseBranch
            )

            // Store metadata (folderName + createdAt only)
            let metadata = WorktreeMetadata(folderName: folderName)
            await store.addWorktreeMetadata(metadata, repositoryID: repository.id)

            // Copy files if enabled (.worktreeinclude patterns or .env* fallback)
            let fileCopyOverride = await store.getEnvCopyOverride(for: repository.id)
            let globalDefault = UserDefaults.standard.object(forKey: "copyEnvFilesEnabled") as? Bool ?? true
            let shouldCopyFiles = fileCopyOverride ?? globalDefault
            if shouldCopyFiles {
                let copyResult = fileCopier.copyFiles(from: repository.path, to: newWorktree.path)
                if !copyResult.errors.isEmpty {
                    errorMessage = "Some files could not be copied: \(copyResult.errors.joined(separator: ", "))"
                }
            }

            // Refresh list and select the new worktree
            await loadWorktrees()
            selectedWorktree = worktrees.first { $0.path == newWorktree.path }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Remove Worktree

    func removeWorktree(_ worktree: Worktree, force: Bool = false) async {
        guard let repository else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await worktreeManager.removeWorktree(
                repositoryPath: repository.path,
                worktreePath: worktree.path,
                force: force
            )

            // Remove metadata
            await store.removeWorktreeMetadata(
                folderName: worktree.folderName,
                repositoryID: repository.id
            )

            if selectedWorktree?.id == worktree.id {
                selectedWorktree = nil
            }

            await loadWorktrees()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeSelectedWorktree(force: Bool = false) async {
        guard let selected = selectedWorktree else { return }
        await removeWorktree(selected, force: force)
    }

    // MARK: - Git Pull

    func gitPull(_ worktree: Worktree) async {
        guard repository != nil else { return }
        guard !pullingWorktrees.contains(worktree.id) else { return }

        pullResultMessage = nil
        isLoading = true
        pullingWorktrees.insert(worktree.id)

        do {
            let result = try await worktreeManager.gitPull(worktreePath: worktree.path)
            pullResultMessage = result.summary
            await loadWorktrees()
        } catch {
            pullResultMessage = nil
            errorMessage = error.localizedDescription
        }

        // Clean up after all async work completes
        isLoading = false
        pullingWorktrees.remove(worktree.id)
    }

    func clearPullResult() {
        pullResultMessage = nil
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

        // Update local state immediately
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
        // Update local state
        if let index = worktrees.firstIndex(where: { $0.id == worktree.id }) {
            worktrees[index].lastActivityAt = Date()
        }
    }

    // MARK: - Tool Availability

    var isITermAvailable: Bool {
        toolLauncher.isITermInstalled()
    }

    var isGhosttyAvailable: Bool {
        toolLauncher.isGhosttyInstalled()
    }

    var isVSCodeAvailable: Bool {
        toolLauncher.isVSCodeInstalled()
    }

    var isCursorAvailable: Bool {
        toolLauncher.isCursorInstalled()
    }

    var isCmuxAvailable: Bool {
        toolLauncher.isCmuxInstalled()
    }

    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
    }
}
