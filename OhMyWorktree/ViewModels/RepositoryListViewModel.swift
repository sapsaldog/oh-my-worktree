import Foundation
import SwiftUI

@MainActor
final class RepositoryListViewModel: ObservableObject {
    @Published var repositories: [Repository] = []
    @Published var selectedRepository: Repository?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingFileDialog = false

    let store: RepositoryStore

    init(store: RepositoryStore = .shared) {
        self.store = store
    }

    // MARK: - Load

    func loadRepositories() async {
        isLoading = true
        defer { isLoading = false }

        repositories = await store.getRepositories()

        // Restore last selected repository
        if selectedRepository == nil, let first = repositories.first {
            selectedRepository = first
        }

        // If selected repository no longer exists in list, reset
        if let selected = selectedRepository,
           !repositories.contains(where: { $0.id == selected.id }) {
            selectedRepository = repositories.first
        }
    }

    // MARK: - Add

    func addRepository(at path: String, name: String? = nil) async {
        let resolvedName = name ?? (path as NSString).lastPathComponent
        let repository = Repository(name: resolvedName, path: path)

        // Validate it's a git repository
        let manager = WorktreeManager()
        let isValid = await manager.isValidGitRepository(path: path)

        guard isValid else {
            errorMessage = OhMyWorktreeError.invalidGitRepository(path: path).errorDescription
            return
        }

        await store.addRepository(repository)
        await loadRepositories()

        // Auto-select the newly added repository
        selectedRepository = repositories.first { $0.path == path }
    }

    // MARK: - Remove

    func removeRepository(_ repository: Repository) async {
        await store.removeRepository(id: repository.id)

        if selectedRepository?.id == repository.id {
            selectedRepository = nil
        }

        await loadRepositories()
    }

    func removeSelectedRepository() async {
        guard let selected = selectedRepository else { return }
        await removeRepository(selected)
    }

    // MARK: - Select

    func selectRepository(_ repository: Repository) async {
        selectedRepository = repository
        await store.updateLastAccessed(id: repository.id)
    }

    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
    }
}
