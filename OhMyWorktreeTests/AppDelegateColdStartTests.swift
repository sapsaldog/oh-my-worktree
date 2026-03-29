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

        let menuItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: "")
        appDelegate.settingsClicked(menuItem)

        let settingsWindows = NSApp.windows.filter { $0.title == AppDelegate.settingsWindowTitle }
        XCTAssertEqual(settingsWindows.count, 1, "Settings window should be created on cold start")
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

    func testSettingsWindowIsReused() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.updaterManager = UpdaterManager()

        let menuItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: "")
        appDelegate.settingsClicked(menuItem)
        appDelegate.settingsClicked(menuItem)

        let settingsWindows = NSApp.windows.filter { $0.title == AppDelegate.settingsWindowTitle }
        XCTAssertEqual(settingsWindows.count, 1, "Clicking Settings twice should reuse the same window")
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

    func testSettingsWindowUsesExpectedTitle() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.updaterManager = UpdaterManager()

        appDelegate.showOrCreateSettingsWindow()

        let settingsWindows = NSApp.windows.filter { $0.title == AppDelegate.settingsWindowTitle }
        XCTAssertEqual(settingsWindows.count, 1,
                       "Settings window title should match AppDelegate.settingsWindowTitle")
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

    // MARK: - Settings view does not impose a fixed size that conflicts with window

    func testSettingsViewIntrinsicSizeIsNotFixedFramePlusPadding() async throws {
        // The Settings window sets its own content size to 400x500.
        // If SettingsView also has .frame(width: 400, height: 500).padding(),
        // the padding adds ~16pt on each side OUTSIDE the frame, inflating
        // the hosting view's intrinsic content size to exactly 432x532.
        // This causes the view to overflow the 400x500 window.
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.updaterManager = UpdaterManager()

        appDelegate.showOrCreateSettingsWindow()

        guard let window = NSApp.windows.first(where: { $0.title == AppDelegate.settingsWindowTitle }),
              let hostingView = window.contentView
        else {
            XCTFail("Settings window with hosting view should exist")
            return
        }

        let intrinsicSize = hostingView.intrinsicContentSize

        // With the redundant .frame(400,500).padding() pattern, intrinsic size
        // would be exactly 432x532 (400+32, 500+32). After removing the redundant
        // .frame(), the view flexibly fills the window and its intrinsic width
        // should NOT be 432 (the telltale sign of the overflow bug).
        let buggyWidth: CGFloat = 432
        let buggyHeight: CGFloat = 532
        let tolerance: CGFloat = 2

        let hasRedundantFrame =
            abs(intrinsicSize.width - buggyWidth) < tolerance &&
            abs(intrinsicSize.height - buggyHeight) < tolerance

        XCTAssertFalse(
            hasRedundantFrame,
            "SettingsView should not impose a fixed 400x500 frame; "
            + "the NSWindow owns the sizing. Intrinsic size was "
            + "\(intrinsicSize.width)x\(intrinsicSize.height), which matches "
            + "the .frame(400,500).padding() overflow pattern."
        )
    }
}
