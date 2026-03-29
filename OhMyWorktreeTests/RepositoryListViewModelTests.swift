import XCTest

@testable import OhMyWorktree

@MainActor
final class RepositoryListViewModelTests: XCTestCase {

    private var sut: RepositoryListViewModel!
    private let testDefaults = UserDefaults(suiteName: "RepositoryListViewModelTests")!

    override func setUp() async throws {
        try await super.setUp()
        testDefaults.removePersistentDomain(forName: "RepositoryListViewModelTests")
        sut = RepositoryListViewModel(userDefaults: testDefaults)
    }

    override func tearDown() async throws {
        sut = nil
        testDefaults.removePersistentDomain(forName: "RepositoryListViewModelTests")
        try await super.tearDown()
    }

    // MARK: - selectRepository persists ID to UserDefaults

    func testSelectRepository_savesIDToUserDefaults() async {
        let repo = Repository(name: "test-repo", path: "/tmp/test-repo-save")

        await sut.selectRepository(repo)

        let savedID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        XCTAssertEqual(savedID, repo.id.uuidString)
    }

    func testSelectRepository_overwritesPreviousSavedID() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-overwrite-1")
        let repo2 = Repository(name: "repo-2", path: "/tmp/repo-overwrite-2")

        await sut.selectRepository(repo1)
        await sut.selectRepository(repo2)

        let savedID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        XCTAssertEqual(savedID, repo2.id.uuidString)
    }

    // MARK: - loadRepositories restores from UserDefaults

    func testLoadRepositories_restoresLastSelectedFromUserDefaults() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-restore-1")
        let repo2 = Repository(name: "repo-2", path: "/tmp/repo-restore-2")

        await sut.store.addRepository(repo1)
        await sut.store.addRepository(repo2)

        // Simulate a saved selection for repo2
        testDefaults.set(repo2.id.uuidString, forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)

        await sut.loadRepositories()

        XCTAssertEqual(sut.selectedRepository?.id, repo2.id)

        // Cleanup
        await sut.store.removeRepository(id: repo1.id)
        await sut.store.removeRepository(id: repo2.id)
    }

    func testLoadRepositories_fallsBackToFirstWhenSavedIDNotFound() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-fallback-1")

        await sut.store.addRepository(repo1)

        // Simulate a saved selection that no longer exists
        testDefaults.set(UUID().uuidString, forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)

        await sut.loadRepositories()

        // Should select something (falls back to first available)
        XCTAssertNotNil(sut.selectedRepository)

        // Cleanup
        await sut.store.removeRepository(id: repo1.id)
    }

    func testLoadRepositories_fallsBackToFirstWhenNoSavedID() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-nosaved-1")

        await sut.store.addRepository(repo1)

        // No saved ID in UserDefaults
        await sut.loadRepositories()

        // Should select something
        XCTAssertNotNil(sut.selectedRepository)

        // Cleanup
        await sut.store.removeRepository(id: repo1.id)
    }

    func testLoadRepositories_preservesCurrentSelectionIfStillValid() async {
        let repo1 = Repository(name: "repo-1", path: "/tmp/repo-preserve-1")
        let repo2 = Repository(name: "repo-2", path: "/tmp/repo-preserve-2")

        await sut.store.addRepository(repo1)
        await sut.store.addRepository(repo2)

        await sut.loadRepositories()
        sut.selectedRepository = repo2

        // Reload — should keep current selection since repo2 still exists
        await sut.loadRepositories()

        XCTAssertEqual(sut.selectedRepository?.id, repo2.id)

        // Cleanup
        await sut.store.removeRepository(id: repo1.id)
        await sut.store.removeRepository(id: repo2.id)
    }

    // MARK: - addRepository persists selection to UserDefaults

    func testAddRepository_persistsSelectionToUserDefaults() async {
        let uuid = UUID().uuidString
        let path = "/tmp/test-add-persist-\(uuid)"

        // Create a real git repo so addRepository validation passes
        let fm = FileManager.default
        try? fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", path]
        try? process.run()
        process.waitUntilExit()

        // Act
        await sut.addRepository(at: path)

        // Assert — UserDefaults must contain the new repo's ID
        let savedIDString = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        XCTAssertNotNil(savedIDString, "UserDefaults should contain a saved repository ID after addRepository")

        let addedRepo = sut.repositories.first(where: { $0.path == path })
        XCTAssertNotNil(addedRepo, "The repository should exist in the list")
        XCTAssertEqual(savedIDString, addedRepo?.id.uuidString,
                       "UserDefaults should persist the ID of the newly added repository")

        // Cleanup
        if let repo = addedRepo {
            await sut.store.removeRepository(id: repo.id)
        }
        try? fm.removeItem(atPath: path)
    }

    // MARK: - removeRepository clears UserDefaults

    func testRemoveRepository_clearsUserDefaultsWhenSelectedRepoRemoved() async {
        let repo = Repository(name: "repo-remove", path: "/tmp/repo-remove-defaults")

        // Add repo to store and select it (persists ID to UserDefaults)
        await sut.store.addRepository(repo)
        await sut.selectRepository(repo)

        // Verify UserDefaults has the repo's ID
        let savedID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        XCTAssertEqual(savedID, repo.id.uuidString, "Precondition: UserDefaults should have the selected repo ID")

        // Remove the selected repository
        await sut.removeRepository(repo)

        // Assert that UserDefaults no longer has the removed repo's stale ID
        // (loadRepositories may set a new fallback ID if other repos exist in the shared store)
        let afterRemoveID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        XCTAssertNotEqual(afterRemoveID, repo.id.uuidString,
                          "UserDefaults should not contain the removed repository's ID")

        // Cleanup
        await sut.store.removeRepository(id: repo.id)
    }

    // MARK: - loadRepositories persists fallback selection

    func testLoadRepositories_persistsFallbackSelectionToUserDefaults() async {
        let repo = Repository(name: "repo-persist", path: "/tmp/repo-persist-fallback")

        await sut.store.addRepository(repo)

        // Simulate a stale/invalid UUID saved from a previously removed repo
        let staleID = UUID()
        testDefaults.set(staleID.uuidString, forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)

        await sut.loadRepositories()

        // The fallback repo should be selected (not nil)
        XCTAssertNotNil(sut.selectedRepository)

        // UserDefaults should NOW contain the selected fallback repo's ID, not the stale one
        let persistedID = testDefaults.string(forKey: RepositoryListViewModel.lastSelectedRepositoryIDKey)
        XCTAssertNotNil(persistedID, "Fallback selection should be persisted to UserDefaults")
        XCTAssertEqual(persistedID, sut.selectedRepository?.id.uuidString,
                       "Persisted ID should match the selected fallback repository")
        XCTAssertNotEqual(persistedID, staleID.uuidString, "Stale ID should have been replaced")

        // Cleanup
        await sut.store.removeRepository(id: repo.id)
    }

    func testLoadRepositories_resetsSelectionWhenSelectedRepoRemoved() async {
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
        XCTAssertNotEqual(sut.selectedRepository?.id, repo2.id)
        XCTAssertNotNil(sut.selectedRepository)

        // Cleanup
        await sut.store.removeRepository(id: repo1.id)
    }
}
