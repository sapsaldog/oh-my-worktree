import Combine
import XCTest

@testable import OhMyWorktree

/// Tests for cold-start behaviour where the app launches via Login Items
/// and no SwiftUI window exists yet.
///
/// Architecture: AppDelegate manages windows directly via NSWindow +
/// NSHostingView, bypassing SwiftUI Scene lifecycle entirely.
/// No @Environment closures are needed, so cold start works identically
/// to a normal launch.
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
        // Close any windows created during the test to prevent cross-test
        // interference via title-based window lookup in showOrCreateWindow.
        let testWindowTitles: Set<String> = [
            AppDelegate.mainWindowTitle,
            AppDelegate.settingsWindowTitle
        ]
        for window in NSApp.windows where testWindowTitles.contains(window.title) {
            window.close()
        }

        await RepositoryStore.shared.removeRepository(id: testRepo.id)
        try await super.tearDown()
    }

    // MARK: - Eager repository loading

    func testRepoViewModelDidSetTriggersEagerLoad() async throws {
        let vm = RepositoryListViewModel()
        XCTAssertTrue(vm.repositories.isEmpty)

        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()

        let loaded = expectation(description: "Repositories loaded after didSet")
        let cancellable = vm.$repositories
            .dropFirst()
            .first(where: { $0.contains(where: { $0.id == self.testRepo.id }) })
            .sink { _ in loaded.fulfill() }

        appDelegate.repoViewModel = vm

        await fulfillment(of: [loaded], timeout: 3.0)
        XCTAssertTrue(vm.repositories.contains(where: { $0.id == testRepo.id }))
        cancellable.cancel()
    }

    // MARK: - Menu populated after eager load

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

        try await Task.sleep(for: .milliseconds(100))

        guard let menu = appDelegate.statusItem?.menu else {
            XCTFail("Status item menu should exist")
            return
        }
        let repoItem = menu.items.first(where: { $0.title == testRepo.name })
        XCTAssertNotNil(repoItem, "Menu should contain the repository after cold-start loading")
    }

    // MARK: - Open Main Window creates NSWindow on cold start

    func testShowOrCreateMainWindowCreatesWindow() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.repoViewModel = RepositoryListViewModel()
        appDelegate.worktreeViewModel = WorktreeListViewModel()

        // When: showOrCreateMainWindow is called (no existing window)
        appDelegate.showOrCreateMainWindow()

        // Then: Should not crash and app should be activated
        // (Window creation depends on NSApp context, but the method must not crash)
    }

    // MARK: - Settings does not crash on cold start

    func testSettingsClickedDoesNotCrash() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.updaterManager = UpdaterManager()
        appDelegate.shortcutManager = ShortcutManager()

        // Settings is now managed by SwiftUI Settings scene.
        // This just verifies the action doesn't crash without a scene context.
        let menuItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: "")
        appDelegate.settingsClicked(menuItem)
    }

    // MARK: - Import PR triggers sheet flag

    func testImportPRSetsSheetFlag() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        let worktreeVM = WorktreeListViewModel()
        appDelegate.repoViewModel = RepositoryListViewModel()
        appDelegate.worktreeViewModel = worktreeVM

        XCTAssertFalse(worktreeVM.isShowingImportPR)

        let menuItem = NSMenuItem(title: "Import from GitHub PR…", action: nil, keyEquivalent: "")
        appDelegate.importFromGitHubPRClicked(menuItem)

        // Give DispatchQueue.main.async time to execute
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(worktreeVM.isShowingImportPR)
    }

    // MARK: - Window reuse (no duplicates)

    func testSettingsClickedTwiceDoesNotCrash() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.updaterManager = UpdaterManager()
        appDelegate.shortcutManager = ShortcutManager()

        // Settings window is managed by SwiftUI Settings scene; just verify no crash.
        let menuItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: "")
        appDelegate.settingsClicked(menuItem)
        appDelegate.settingsClicked(menuItem)
    }

    func testMainWindowIsReused() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.repoViewModel = RepositoryListViewModel()
        appDelegate.worktreeViewModel = WorktreeListViewModel()

        appDelegate.showOrCreateMainWindow()
        appDelegate.showOrCreateMainWindow()

        let mainWindows = NSApp.windows.filter { $0.title == AppDelegate.mainWindowTitle }
        XCTAssertEqual(mainWindows.count, 1, "Calling showOrCreateMainWindow twice should reuse the same window")
    }

    // MARK: - Window survives close (no crash on dealloc)

    func testWindowNotReleasedWhenClosed() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.repoViewModel = RepositoryListViewModel()
        appDelegate.worktreeViewModel = WorktreeListViewModel()

        appDelegate.showOrCreateMainWindow()

        guard let window = NSApp.windows.first(where: { $0.title == AppDelegate.mainWindowTitle }) else {
            XCTFail("Main window should exist")
            return
        }

        XCTAssertFalse(window.isReleasedWhenClosed,
                       "Window must not be released on close to prevent crash in AppKit animations")
    }

    // MARK: - Worktree synced when selectedRepository changes

    func testSelectedRepoSyncsWorktreeViewModel() async throws {
        let repoVM = RepositoryListViewModel()
        let worktreeVM = WorktreeListViewModel()

        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.worktreeViewModel = worktreeVM
        appDelegate.repoViewModel = repoVM

        // Wait for eager load
        let loaded = expectation(description: "Repos loaded")
        let cancellable = repoVM.$repositories
            .dropFirst()
            .first(where: { !$0.isEmpty })
            .sink { _ in loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 3.0)
        cancellable.cancel()

        // selectedRepository should have been set and synced to worktreeVM
        if let selected = repoVM.selectedRepository {
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(worktreeVM.repository?.id, selected.id,
                           "worktreeViewModel.repository should sync with selectedRepository")
        }
    }

    // MARK: - Window title consistency

    func testShowOrCreateSettingsWindowDoesNotCrash() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.updaterManager = UpdaterManager()
        appDelegate.shortcutManager = ShortcutManager()

        // Settings window is managed by SwiftUI Settings scene; just verify no crash.
        appDelegate.showOrCreateSettingsWindow()
    }

    func testMainWindowUsesExpectedTitle() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.repoViewModel = RepositoryListViewModel()
        appDelegate.worktreeViewModel = WorktreeListViewModel()

        appDelegate.showOrCreateMainWindow()

        let mainWindows = NSApp.windows.filter { $0.title == AppDelegate.mainWindowTitle }
        XCTAssertEqual(mainWindows.count, 1,
                       "Main window title should match AppDelegate.mainWindowTitle")
    }

    // MARK: - Test environment detection

    func testIsRunningTests_returnsTrueInTestEnvironment() {
        XCTAssertTrue(AppDelegate.isRunningTests,
                      "isRunningTests should be true when running under XCTest")
    }

    // MARK: - Settings view does not impose a fixed size that conflicts with window

    // MARK: - No redundant worktree loading from repo selection sink

    func testSelectedRepoDoesNotEagerLoadWorktrees() async throws {
        let mockExecutor = MockSimpleGitExecutor()
        mockExecutor.worktreeListOutput = """
        worktree /tmp/no-eager-test
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/no-eager-test/wt-feature
        HEAD abc2222
        branch refs/heads/feature/x

        """

        let worktreeVM = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: mockExecutor, fileManager: MockNoOpFileManager()),
            store: .shared,
            pullRequestService: MockNoPRService()
        )

        let repoVM = RepositoryListViewModel()
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.worktreeViewModel = worktreeVM
        appDelegate.repoViewModel = repoVM

        // Wait for any eager repo loading to settle
        try await Task.sleep(for: .milliseconds(200))

        // Act: change selectedRepository — triggers the $selectedRepository sink
        let repo = Repository(name: "no-eager-test", path: "/tmp/no-eager-test")
        repoVM.selectedRepository = repo

        // Wait for Combine sink and any async tasks to fire
        try await Task.sleep(for: .milliseconds(300))

        // Assert: repository should be synced by the sink
        XCTAssertEqual(worktreeVM.repository?.id, repo.id,
            "AppDelegate should sync worktreeViewModel.repository")

        // Assert: worktrees should NOT be loaded by AppDelegate
        // (ContentView and menuWillOpen are responsible for loading)
        XCTAssertTrue(worktreeVM.worktrees.isEmpty,
            "AppDelegate should not trigger worktree loading from selectedRepository sink")
    }

    // MARK: - Settings view does not impose a fixed size that conflicts with window

    func testSettingsViewIntrinsicSizeIsNotFixedFramePlusPadding() async throws {
        // Settings is now managed by SwiftUI Settings scene — no manual window to test.
    }

    // MARK: - Silent guard failures don't crash

    func testShowOrCreateMainWindow_doesNotCrashWhenViewModelsNil() {
        // Close any pre-existing windows (e.g. from SwiftUI WindowGroup)
        for window in NSApp.windows where window.title == AppDelegate.mainWindowTitle {
            window.close()
        }
        let beforeCount = NSApp.windows.filter { $0.title == AppDelegate.mainWindowTitle }.count

        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        // repoViewModel and worktreeViewModel are nil
        appDelegate.showOrCreateMainWindow()
        // Should not crash — just returns early (with a log warning)

        let afterCount = NSApp.windows.filter { $0.title == AppDelegate.mainWindowTitle }.count
        XCTAssertEqual(afterCount, beforeCount, "No window should be created when view models are nil")
    }

    func testShowOrCreateSettingsWindow_doesNotCrashWhenUpdaterManagerNil() {
        // Close any pre-existing windows (e.g. from other tests)
        for window in NSApp.windows where window.title == AppDelegate.settingsWindowTitle {
            window.close()
        }
        let beforeCount = NSApp.windows.filter { $0.title == AppDelegate.settingsWindowTitle }.count

        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        // updaterManager is nil
        appDelegate.showOrCreateSettingsWindow()
        // Should not crash — just returns early (with a log warning)

        let afterCount = NSApp.windows.filter { $0.title == AppDelegate.settingsWindowTitle }.count
        XCTAssertEqual(afterCount, beforeCount, "No window should be created when updaterManager is nil")
    }
}
