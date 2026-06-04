import Foundation
import Testing

@testable import OhMyWorktree

@Suite(.serialized) @MainActor
struct RepositoryListViewModelTests {

    private let sut: RepositoryListViewModel
    private let testDefaults: UserDefaults

    init() {
        let testDefaults = UserDefaults(suiteName: "RepositoryListViewModelTests")!
        testDefaults.removePersistentDomain(forName: "RepositoryListViewModelTests")
        self.testDefaults = testDefaults
        self.sut = RepositoryListViewModel(userDefaults: testDefaults)
    }

    // MARK: - selectRepository persists ID to UserDefaults

    @Test func selectRepository_savesIDToUserDefaults() async {
        let repo = Repository(name: "test-repo", path: "/tmp/test-repo-save")

        await sut.selectRepository(repo)

        let savedID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        #expect(savedID == repo.id.uuidString)
    }

    @Test func selectRepository_overwritesPreviousSavedID() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-overwrite-1")
        let repo2 = Repository(name: "repo-2", path: "/tmp/repo-overwrite-2")

        await sut.selectRepository(repo1)
        await sut.selectRepository(repo2)

        let savedID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        #expect(savedID == repo2.id.uuidString)
    }

    // MARK: - loadRepositories restores from UserDefaults

    @Test func loadRepositories_restoresLastSelectedFromUserDefaults() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-restore-1")
        let repo2 = Repository(name: "repo-2", path: "/tmp/repo-restore-2")

        await sut.store.addRepository(repo1)
        await sut.store.addRepository(repo2)

        // Simulate a saved selection for repo2
        testDefaults.set(repo2.id.uuidString, forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)

        await sut.loadRepositories()

        #expect(sut.selectedRepository?.id == repo2.id)

        // Cleanup
        await sut.store.removeRepository(id: repo1.id)
        await sut.store.removeRepository(id: repo2.id)
    }

    @Test func loadRepositories_fallsBackToFirstWhenSavedIDNotFound() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-fallback-1")

        await sut.store.addRepository(repo1)

        // Simulate a saved selection that no longer exists
        testDefaults.set(UUID().uuidString, forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)

        await sut.loadRepositories()

        // Should fall back to a valid repository from the list
        #expect(sut.selectedRepository != nil,
                "Should select a fallback repository")
        #expect(sut.repositories.contains(where: { $0.id == sut.selectedRepository?.id }),
              "Selected repository should be in the repositories list")

        // Cleanup
        await sut.store.removeRepository(id: repo1.id)
    }

    @Test func loadRepositories_fallsBackToFirstWhenNoSavedID() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-nosaved-1")

        await sut.store.addRepository(repo1)

        // No saved ID in UserDefaults
        await sut.loadRepositories()

        // Should fall back to a valid repository from the list
        #expect(sut.selectedRepository != nil,
                "Should select a fallback repository")
        #expect(sut.repositories.contains(where: { $0.id == sut.selectedRepository?.id }),
              "Selected repository should be in the repositories list")

        // Cleanup
        await sut.store.removeRepository(id: repo1.id)
    }

    @Test func loadRepositories_preservesCurrentSelectionIfStillValid() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-preserve-1")
        let repo2 = Repository(name: "repo-2", path: "/tmp/repo-preserve-2")

        await sut.store.addRepository(repo1)
        await sut.store.addRepository(repo2)

        await sut.loadRepositories()
        sut.selectedRepository = repo2

        // Reload — should keep current selection since repo2 still exists
        await sut.loadRepositories()

        #expect(sut.selectedRepository?.id == repo2.id)

        // Cleanup
        await sut.store.removeRepository(id: repo1.id)
        await sut.store.removeRepository(id: repo2.id)
    }

    // MARK: - addRepository persists selection to UserDefaults

    @Test func addRepository_persistsSelectionToUserDefaults() async throws {
        let uuid = UUID().uuidString
        let path = "/tmp/test-add-persist-\(uuid)"

        // Create a real git repo so addRepository validation passes
        let fm = FileManager.default
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "git init must succeed for this test to be valid")

        // Act
        await sut.addRepository(at: path)

        // Assert — UserDefaults must contain the new repo's ID
        let savedIDString = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        #expect(savedIDString != nil, "UserDefaults should contain a saved repository ID after addRepository")

        let addedRepo = sut.repositories.first(where: { $0.path == path })
        #expect(addedRepo != nil, "The repository should exist in the list")
        #expect(savedIDString == addedRepo?.id.uuidString,
               "UserDefaults should persist the ID of the newly added repository")

        // Cleanup
        if let repo = addedRepo {
            await sut.store.removeRepository(id: repo.id)
        }
        try? fm.removeItem(atPath: path)
    }

    // MARK: - removeRepository clears UserDefaults

    @Test func removeRepository_clearsUserDefaultsWhenSelectedRepoRemoved() async {
        let repo = Repository(name: "repo-remove", path: "/tmp/repo-remove-defaults")

        // Add repo to store and select it (persists ID to UserDefaults)
        await sut.store.addRepository(repo)
        await sut.selectRepository(repo)

        // Verify UserDefaults has the repo's ID
        let savedID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        #expect(savedID == repo.id.uuidString, "Precondition: UserDefaults should have the selected repo ID")

        // Remove the selected repository
        await sut.removeRepository(repo)

        // Assert that UserDefaults no longer has the removed repo's stale ID
        // (loadRepositories may set a new fallback ID if other repos exist in the shared store)
        let afterRemoveID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        #expect(afterRemoveID != repo.id.uuidString,
                "UserDefaults should not contain the removed repository's ID")

        // Cleanup
        await sut.store.removeRepository(id: repo.id)
    }

    // MARK: - selectNextRepository persists to UserDefaults

    @Test func selectNextRepository_persistsToUserDefaults() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-next-persist-1")
        let repo2 = Repository(name: "repo-2", path: "/tmp/repo-next-persist-2")

        sut.repositories = [repo1, repo2]
        sut.selectedRepository = repo1

        await sut.selectNextRepository()

        let savedID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        #expect(savedID == repo2.id.uuidString,
               "selectNextRepository should persist the new selection to UserDefaults")
    }

    // MARK: - selectPreviousRepository persists to UserDefaults

    @Test func selectPreviousRepository_persistsToUserDefaults() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-prev-persist-1")
        let repo2 = Repository(name: "repo-2", path: "/tmp/repo-prev-persist-2")

        sut.repositories = [repo1, repo2]
        sut.selectedRepository = repo2

        await sut.selectPreviousRepository()

        let savedID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        #expect(savedID == repo1.id.uuidString,
               "selectPreviousRepository should persist the new selection to UserDefaults")
    }

    // MARK: - loadRepositories persists fallback selection

    @Test func loadRepositories_persistsFallbackSelectionToUserDefaults() async {
        let repo = Repository(name: "repo-persist", path: "/tmp/repo-persist-fallback")

        await sut.store.addRepository(repo)

        // Simulate a stale/invalid UUID saved from a previously removed repo
        let staleID = UUID()
        testDefaults.set(staleID.uuidString, forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)

        await sut.loadRepositories()

        // The fallback repo should be selected (not nil)
        #expect(sut.selectedRepository != nil)

        // UserDefaults should NOW contain the selected fallback repo's ID, not the stale one
        let persistedID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        #expect(persistedID != nil, "Fallback selection should be persisted to UserDefaults")
        #expect(persistedID == sut.selectedRepository?.id.uuidString,
               "Persisted ID should match the selected fallback repository")
        #expect(persistedID != staleID.uuidString, "Stale ID should have been replaced")

        // Cleanup
        await sut.store.removeRepository(id: repo.id)
    }

    @Test func loadRepositories_resetsSelectionWhenSelectedRepoRemoved() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-reset-1")
        let repo2 = Repository(name: "repo-2", path: "/tmp/repo-reset-2")

        await sut.store.addRepository(repo1)
        await sut.store.addRepository(repo2)

        await sut.loadRepositories()
        sut.selectedRepository = repo2

        // Remove repo2
        await sut.store.removeRepository(id: repo2.id)
        await sut.loadRepositories()

        // Should no longer be repo2; should fall back to some valid repo
        #expect(sut.selectedRepository?.id != repo2.id)
        #expect(sut.selectedRepository != nil)

        // Cleanup
        await sut.store.removeRepository(id: repo1.id)
    }

    // MARK: - loadRepositories clears selection + UserDefaults when store is empty

    @Test func loadRepositories_clearsSelectionAndUserDefaultsWhenStoreEmpty() async {
        // Drain the shared store so getRepositories() returns an empty list.
        // The suite is serialized, so no other test runs concurrently; we restore at the end.
        let existing = await sut.store.getRepositories()
        for repo in existing {
            await sut.store.removeRepository(id: repo.id)
        }

        // Select a phantom repository that is NOT in the (now empty) store and persist its ID.
        let phantom = Repository(name: "phantom", path: "/tmp/repo-empty-phantom")
        sut.selectedRepository = phantom
        testDefaults.set(phantom.id.uuidString, forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)

        await sut.loadRepositories()

        // Empty store → no fallback → selection cleared and UserDefaults key removed.
        #expect(sut.repositories.isEmpty)
        #expect(sut.selectedRepository == nil)
        #expect(testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey) == nil)

        // Restore the store to its prior contents.
        for repo in existing {
            await sut.store.addRepository(repo)
        }
    }

    // MARK: - addRepository invalid path surfaces error

    @Test func addRepository_invalidGitRepository_setsErrorAndDoesNotAdd() async throws {
        // A real directory that is NOT a git repository → isValidGitRepository == false.
        let path = "/tmp/repo-invalid-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        defer { try? fm.removeItem(atPath: path) }

        await sut.addRepository(at: path)

        #expect(sut.errorMessage != nil, "Invalid git repository should set an error message")
        #expect(false == sut.repositories.contains(where: { $0.path == path }),
                "Invalid repository must not be added")
    }

    // MARK: - removeSelectedRepository

    @Test func removeSelectedRepository_removesCurrentSelection() async {
        let repo = Repository(name: "repo-remove-selected", path: "/tmp/repo-remove-selected")
        await sut.store.addRepository(repo)
        await sut.selectRepository(repo)
        #expect(sut.selectedRepository?.id == repo.id)

        await sut.removeSelectedRepository()

        // The removed repo must no longer be the selection nor in the store.
        #expect(sut.selectedRepository?.id != repo.id)
        let stored = await sut.store.getRepositories()
        #expect(false == stored.contains(where: { $0.id == repo.id }))

        // Cleanup (best-effort; already removed).
        await sut.store.removeRepository(id: repo.id)
    }

    @Test func removeSelectedRepository_noSelection_doesNothing() async {
        sut.selectedRepository = nil

        // Guard path: returns early without touching the store.
        await sut.removeSelectedRepository()

        #expect(sut.selectedRepository == nil)
    }

    // MARK: - clearError

    @Test func clearError_resetsErrorMessage() {
        sut.errorMessage = "boom"
        #expect(sut.errorMessage != nil)

        sut.clearError()

        #expect(sut.errorMessage == nil)
    }
}
