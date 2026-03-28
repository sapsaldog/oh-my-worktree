import Combine
import XCTest

@testable import OhMyWorktree

/// Tests for the cold-start race condition fix where the menu bar would show
/// an empty repository list when the app launched via Login Items on reboot.
///
/// Root cause: `repoViewModel` was only connected to AppDelegate in
/// ContentView's `.onAppear`, and `loadRepositories()` was only called in
/// ContentView's `.task`. If the main window hadn't appeared yet, the menu
/// bar had no data.
///
/// Fix: `repoViewModel.didSet` now eagerly loads repositories and subscribes
/// to changes via Combine, ensuring the menu is populated regardless of
/// window state.
@MainActor
final class AppDelegateColdStartTests: XCTestCase {

    private var testRepo: Repository!

    override func setUp() async throws {
        try await super.setUp()
        testRepo = Repository(
            name: "cold-start-test",
            path: "/tmp/cold-start-\(UUID().uuidString)"
        )
        await RepositoryStore.shared.addRepository(testRepo)
    }

    override func tearDown() async throws {
        await RepositoryStore.shared.removeRepository(id: testRepo.id)
        try await super.tearDown()
    }

    // MARK: - repoViewModel.didSet triggers eager load

    func testRepoViewModelDidSetTriggersEagerLoad() async throws {
        // Given: A fresh ViewModel whose repositories have NOT been loaded
        let vm = RepositoryListViewModel()
        XCTAssertTrue(vm.repositories.isEmpty)

        // When: The ViewModel is assigned to AppDelegate
        // (simulates the moment SwiftUI connects it, before any window appears)
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()

        let loaded = expectation(description: "Repositories loaded after didSet")
        let cancellable = vm.$repositories
            .dropFirst()
            .first(where: { $0.contains(where: { $0.id == self.testRepo.id }) })
            .sink { _ in loaded.fulfill() }

        appDelegate.repoViewModel = vm

        // Then: didSet → observeRepositoryChanges → loadRepositories
        await fulfillment(of: [loaded], timeout: 3.0)
        XCTAssertTrue(vm.repositories.contains(where: { $0.id == testRepo.id }))
        cancellable.cancel()
    }

    // MARK: - Menu is populated after cold-start load

    func testMenuPopulatedAfterColdStartLoad() async throws {
        let vm = RepositoryListViewModel()
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()

        let loaded = expectation(description: "Repositories loaded")
        let cancellable = vm.$repositories
            .dropFirst()
            .first(where: { $0.contains(where: { $0.id == self.testRepo.id }) })
            .sink { _ in loaded.fulfill() }

        appDelegate.repoViewModel = vm
        await fulfillment(of: [loaded], timeout: 3.0)
        cancellable.cancel()

        // Combine subscription in observeRepositoryChanges calls rebuildMenu;
        // give the run loop one tick to process it.
        try await Task.sleep(for: .milliseconds(100))

        // Then: The menu should contain the test repository
        guard let menu = appDelegate.statusItem?.menu else {
            XCTFail("Status item menu should exist")
            return
        }
        let repoItem = menu.items.first(where: { $0.title == testRepo.name })
        XCTAssertNotNil(repoItem, "Menu should contain the repository after cold-start loading")
    }
}
