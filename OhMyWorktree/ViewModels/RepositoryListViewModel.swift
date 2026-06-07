import Foundation
import SwiftUI

@Observable
@MainActor
final class RepositoryListViewModel {
    var repositories: [Repository] = []
    var selectedRepository: Repository?
    var isLoading = false
    var errorMessage: String?
    var showingFileDialog = false

    let store: RepositoryStore
    private let userDefaults: UserDefaults

    static let lastSelectedRepositoryIDKey = "lastSelectedRepositoryID"

    init(store: RepositoryStore = .shared, userDefaults: UserDefaults = .standard) {
        self.store = store
        self.userDefaults = userDefaults
    }

    // MARK: - Load

    func loadRepositories() async {
        isLoading = true
        defer { isLoading = false }

        repositories = await store.getRepositories()

        // Restore last selected repository from UserDefaults
        if selectedRepository == nil {
            if let savedIDString = userDefaults.string(forKey: Self.lastSelectedRepositoryIDKey),
               let savedID = UUID(uuidString: savedIDString),
               let match = repositories.first(where: { $0.id == savedID }) {
                selectedRepository = match
            } else if let first = repositories.first {
                selectedRepository = first
                userDefaults.set(first.id.uuidString, forKey: Self.lastSelectedRepositoryIDKey)
            }
        }

        // If selected repository no longer exists in list, reset
        if let selected = selectedRepository,
           !repositories.contains(where: { $0.id == selected.id }) {
            selectedRepository = repositories.first
            if let fallback = selectedRepository {
                userDefaults.set(fallback.id.uuidString, forKey: Self.lastSelectedRepositoryIDKey)
            } else {
                userDefaults.removeObject(forKey: Self.lastSelectedRepositoryIDKey)
            }
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
        if let newRepo = repositories.first(where: { $0.path == path }) {
            await selectRepository(newRepo)
        }
    }

    // MARK: - Remove

    func removeRepository(_ repository: Repository) async {
        await store.removeRepository(id: repository.id)

        if selectedRepository?.id == repository.id {
            selectedRepository = nil
            userDefaults.removeObject(forKey: Self.lastSelectedRepositoryIDKey)
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
        userDefaults.set(repository.id.uuidString, forKey: Self.lastSelectedRepositoryIDKey)
        await store.updateLastAccessed(id: repository.id)
    }

    // MARK: - Navigation

    func selectNextRepository() async {
        guard !repositories.isEmpty else { return }
        guard let current = selectedRepository,
              let index = repositories.firstIndex(where: { $0.id == current.id }) else {
            if let first = repositories.first {
                await selectRepository(first)
            }
            return
        }
        let nextIndex = index + 1
        guard nextIndex < repositories.count else { return }
        await selectRepository(repositories[nextIndex])
    }

    func selectPreviousRepository() async {
        guard !repositories.isEmpty else { return }
        guard let current = selectedRepository,
              let index = repositories.firstIndex(where: { $0.id == current.id }) else {
            if let first = repositories.first {
                await selectRepository(first)
            }
            return
        }
        let prevIndex = index - 1
        guard prevIndex >= 0 else { return }
        await selectRepository(repositories[prevIndex])
    }

    // MARK: - Reorder

    /// Move the repository identified by `fromID` to the slot currently held by
    /// `toID`, mirroring the prototype's drag-to-reorder, and persist the order.
    func moveRepository(_ fromID: UUID, to toID: UUID) async {
        guard fromID != toID else { return }
        var arr = repositories
        guard let from = arr.firstIndex(where: { $0.id == fromID }),
              let to = arr.firstIndex(where: { $0.id == toID }) else { return }
        let moved = arr.remove(at: from)
        arr.insert(moved, at: to)
        repositories = arr
        await store.reorderRepositories(orderedIDs: arr.map(\.id))
    }

    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
    }
}
