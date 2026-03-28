import Combine
import XCTest

@testable import OhMyWorktree

/// Tests for cold-start race conditions where the menu bar would be broken
/// when the app launched via Login Items on reboot.
///
/// Problems fixed:
/// 1. Empty repository list — `repoViewModel` was only connected and loaded
///    in ContentView's `.onAppear`/`.task`, which depend on window visibility.
/// 2. Non-functional "Open Main Window" and "Settings" — closures capturing
///    `@Environment(\.openWindow)` / `@Environment(\.openSettings)` were set
///    in `.onAppear`, so they stayed nil until the window appeared.
///
/// Fixes:
/// - ViewModel connection moved to Scene body evaluation
/// - `repoViewModel.didSet` eagerly loads repos and subscribes via Combine
/// - Environment closures captured in View `body` (not `.onAppear`)
/// - `settingsClicked` has NSApp fallback for when closures are nil
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

    // MARK: - Settings fallback works without SwiftUI environment

    func testSettingsClickFallbackWhenClosureIsNil() async throws {
        // Given: AppDelegate with NO openSettings closure set
        // (simulates cold start before SwiftUI window appears)
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        XCTAssertNil(appDelegate.openSettings, "openSettings should be nil before window appears")

        // When: settingsClicked is invoked
        // Then: Should not crash (falls back to NSApp.sendAction)
        let menuItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: "")
        appDelegate.settingsClicked(menuItem)
    }

    // MARK: - Open Main Window works without SwiftUI environment

    func testOpenMainWindowWhenClosureIsNil() async throws {
        // Given: AppDelegate with NO openMainWindow closure set
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        XCTAssertNil(appDelegate.openMainWindow, "openMainWindow should be nil before window appears")

        // When: openMainWindowClicked is invoked
        // Then: Should not crash (activates app and searches for existing windows)
        let menuItem = NSMenuItem(title: "Open Main Window", action: nil, keyEquivalent: "")
        appDelegate.openMainWindowClicked(menuItem)
    }
}
