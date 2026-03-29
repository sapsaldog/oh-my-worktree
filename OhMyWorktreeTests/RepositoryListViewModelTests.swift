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
