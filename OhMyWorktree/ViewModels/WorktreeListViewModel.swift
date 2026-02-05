import Foundation
import SwiftUI

@MainActor
final class WorktreeListViewModel: ObservableObject {
    @Published var worktrees: [Worktree] = []
    @Published var selectedWorktree: Worktree?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let worktreeManager: WorktreeManager
    private let toolLauncher: ExternalToolLauncher
    private let store: RepositoryStore

    var repository: Repository?

    init(
        worktreeManager: WorktreeManager = WorktreeManager(),
        toolLauncher: ExternalToolLauncher = ExternalToolLauncher(),
        store: RepositoryStore = RepositoryStore()
    ) {
        self.worktreeManager = worktreeManager
        self.toolLauncher = toolLauncher
        self.store = store
    }

    // MARK: - Load Worktrees

    func loadWorktrees() async {
        guard let repository else {
            worktrees = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Always fetch fresh from git
            worktrees = try await worktreeManager.listWorktrees(repositoryPath: repository.path)

            // If selected worktree no longer exists, reset
            if let selected = selectedWorktree,
               !worktrees.contains(where: { $0.path == selected.path }) {
                selectedWorktree = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            worktrees = []
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

    // MARK: - Open in External Tools

    func openInITerm(_ worktree: Worktree? = nil, mode: AppSettings.OpenMode = .newTab) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }

        do {
            try await toolLauncher.openInITerm(path: target.path, mode: mode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInGhostty(_ worktree: Worktree? = nil) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }

        do {
            try await toolLauncher.openInGhostty(path: target.path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInVSCode(_ worktree: Worktree? = nil, mode: AppSettings.OpenMode = .newWindow) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }

        do {
            try await toolLauncher.openInVSCode(path: target.path, mode: mode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInCursor(_ worktree: Worktree? = nil) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }

        do {
            try await toolLauncher.openInCursor(path: target.path)
        } catch {
            errorMessage = error.localizedDescription
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

    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
    }
}
