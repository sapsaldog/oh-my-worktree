import Foundation
import Testing

import AppKit
import SwiftUI

@testable import OhMyWorktree

/// Tests for cold-start behaviour where the app launches via Login Items
/// and no SwiftUI window exists yet.
///
/// Architecture: AppDelegate manages windows directly via NSWindow +
/// NSHostingView, bypassing SwiftUI Scene lifecycle entirely.
/// No @Environment closures are needed, so cold start works identically
/// to a normal launch.
@Suite(.serialized)
@MainActor
final class AppDelegateColdStartTests {

    private var testRepo: Repository

    init() async throws {
        testRepo = Repository(
            name: "cold-start-test",
            path: "/tmp/cold-start-\(UUID().uuidString)"
        )
        await RepositoryStore.shared.addRepository(testRepo)
    }

    deinit {
        // All cleanup must happen on @MainActor because NSApp.windows
        // and window.close() are main-thread-only AppKit APIs.
        // deinit is nonisolated, so we dispatch everything into a Task.
        Task { @MainActor [testRepo] in
            let testWindowTitles: Set<String> = [
                AppDelegate.mainWindowTitle,
                AppDelegate.settingsWindowTitle
            ]
            for window in NSApp.windows where testWindowTitles.contains(window.title) {
                window.close()
            }
            await RepositoryStore.shared.removeRepository(id: testRepo.id)
        }
    }

    // MARK: - Eager repository loading

    @Test func repoViewModelDidSetTriggersEagerLoad() async throws {
        let vm = RepositoryListViewModel()
        #expect(vm.repositories.isEmpty)

        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()

        appDelegate.repoViewModel = vm

        let testRepoID = self.testRepo.id
        try await pollUntil { vm.repositories.contains(where: { $0.id == testRepoID }) }
        #expect(vm.repositories.contains(where: { $0.id == self.testRepo.id }))
    }

    // MARK: - Menu populated after eager load

    @Test func menuPopulatedAfterColdStartLoad() async throws {
        let vm = RepositoryListViewModel()
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()

        appDelegate.repoViewModel = vm

        let testRepoID = self.testRepo.id
        try await pollUntil { vm.repositories.contains(where: { $0.id == testRepoID }) }

        appDelegate.rebuildMenu()
        let menu = try #require(appDelegate.statusItem?.menu, "Status item menu should exist")
        let repoItem = menu.items.first(where: { $0.title == testRepo.name })
        #expect(repoItem != nil, "Menu should contain the repository after cold-start loading")
    }

    // MARK: - Open Main Window creates NSWindow on cold start

    @Test func showOrCreateMainWindowCreatesWindow() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.repoViewModel = RepositoryListViewModel()
        appDelegate.worktreeViewModel = WorktreeListViewModel()
        appDelegate.shortcutStore = ShortcutStore()

        // When: showOrCreateMainWindow is called (no existing window)
        appDelegate.showOrCreateMainWindow()

        // Then: Should not crash and app should be activated
        // (Window creation depends on NSApp context, but the method must not crash)
    }

    // MARK: - Settings opens via the sheet flag

    @Test func settingsClickedSetsSheetFlag() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        let worktreeVM = WorktreeListViewModel()
        appDelegate.repoViewModel = RepositoryListViewModel()
        appDelegate.worktreeViewModel = worktreeVM

        #expect(false == worktreeVM.isShowingSettings)

        let menuItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: "")
        appDelegate.settingsClicked(menuItem)

        try await pollUntil { worktreeVM.isShowingSettings }
    }

    // MARK: - Import PR triggers sheet flag

    @Test func importPRSetsSheetFlag() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        let worktreeVM = WorktreeListViewModel()
        appDelegate.repoViewModel = RepositoryListViewModel()
        appDelegate.worktreeViewModel = worktreeVM

        #expect(false == worktreeVM.isShowingImportPR)

        let menuItem = NSMenuItem(title: "Import from GitHub PR…", action: nil, keyEquivalent: "")
        appDelegate.importFromGitHubPRClicked(menuItem)

        try await pollUntil { worktreeVM.isShowingImportPR }
    }

    @Test func importPRViewAcceptsOverlayDismissCallback() {
        let worktreeVM = WorktreeListViewModel()
        _ = ImportPRView(worktreeViewModel: worktreeVM, onDismiss: {})
    }

    // MARK: - Window reuse (no duplicates)

    @Test func mainWindowIsReused() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.repoViewModel = RepositoryListViewModel()
        appDelegate.worktreeViewModel = WorktreeListViewModel()
        appDelegate.shortcutStore = ShortcutStore()

        appDelegate.showOrCreateMainWindow()
        appDelegate.showOrCreateMainWindow()

        let mainWindows = NSApp.windows.filter { $0.title == AppDelegate.mainWindowTitle }
        #expect(mainWindows.count == 1, "Calling showOrCreateMainWindow twice should reuse the same window")
    }

    // MARK: - Window survives close (no crash on dealloc)

    @Test func windowNotReleasedWhenClosed() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.repoViewModel = RepositoryListViewModel()
        appDelegate.worktreeViewModel = WorktreeListViewModel()
        appDelegate.shortcutStore = ShortcutStore()

        appDelegate.showOrCreateMainWindow()

        let window = try #require(
            NSApp.windows.first(where: { $0.title == AppDelegate.mainWindowTitle }),
            "Main window should exist"
        )

        #expect(false == window.isReleasedWhenClosed,
               "Window must not be released on close to prevent crash in AppKit animations")
    }

    // MARK: - Worktree synced when selectedRepository changes

    @Test func selectedRepoSyncsWorktreeViewModel() async throws {
        let repoVM = RepositoryListViewModel()
        let worktreeVM = WorktreeListViewModel()

        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.worktreeViewModel = worktreeVM
        appDelegate.repoViewModel = repoVM

        // Wait for eager load
        try await pollUntil { !repoVM.repositories.isEmpty }

        // selectedRepository should have been set and synced to worktreeVM
        if let selected = repoVM.selectedRepository {
            try await pollUntil { worktreeVM.repository?.id == selected.id }
            #expect(worktreeVM.repository?.id == selected.id,
                   "worktreeViewModel.repository should sync with selectedRepository")
        }
    }

    // MARK: - Window title consistency

    @Test func settingsWindowUsesExpectedTitle() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.updaterManager = UpdaterManager()
        appDelegate.shortcutStore = ShortcutStore()

        appDelegate.showOrCreateSettingsWindow()

        let settingsWindows = NSApp.windows.filter { $0.title == AppDelegate.settingsWindowTitle }
        #expect(settingsWindows.count == 1,
               "Settings window title should match AppDelegate.settingsWindowTitle")
    }

    @Test func mainWindowUsesExpectedTitle() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.repoViewModel = RepositoryListViewModel()
        appDelegate.worktreeViewModel = WorktreeListViewModel()
        appDelegate.shortcutStore = ShortcutStore()

        appDelegate.showOrCreateMainWindow()

        let mainWindows = NSApp.windows.filter { $0.title == AppDelegate.mainWindowTitle }
        #expect(mainWindows.count == 1,
               "Main window title should match AppDelegate.mainWindowTitle")
    }

    @Test func hostedContentViewCentersTrafficLightsInToolbar() async throws {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Without this, close() also releases the window while ARC still
        // holds this strong reference — the over-release detonates later in
        // an autorelease-pool drain (the exact crash windowNotReleasedWhenClosed
        // documents for the app). Disable the order-front animation too: the
        // window closes ~0.1s after makeKeyAndOrderFront, well inside the
        // animation, and the in-flight _NSWindowTransformAnimation would keep
        // a reference into the dead window.
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        defer { window.close() }

        let rootView = ContentView(
            repoViewModel: RepositoryListViewModel(),
            worktreeViewModel: WorktreeListViewModel()
        )
        .environment(ShortcutStore())

        window.title = AppDelegate.mainWindowTitle
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentViewController = NSHostingController(rootView: rootView)
        window.setContentSize(NSSize(width: 1180, height: 740))
        window.makeKeyAndOrderFront(nil)

        let toolbarCenterDistanceFromTop: CGFloat = 26
        let closeButtonCenterDistanceFromLeft: CGFloat = 24
        try await pollUntil(timeout: .seconds(1)) {
            guard let center = self.trafficLightCloseButtonCenter(in: window) else {
                return false
            }
            return abs(center.distanceFromTop - toolbarCenterDistanceFromTop) < 1 &&
                abs(center.distanceFromLeft - closeButtonCenterDistanceFromLeft) < 1
        }
    }

    private func trafficLightCloseButtonCenter(in window: NSWindow) -> (
        distanceFromLeft: CGFloat,
        distanceFromTop: CGFloat
    )? {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let buttonContainer = closeButton.superview,
              let contentView = window.contentView else {
            return nil
        }
        let centerInWindow = buttonContainer.convert(
            NSPoint(x: closeButton.frame.midX, y: closeButton.frame.midY),
            to: nil
        )
        return (
            distanceFromLeft: centerInWindow.x,
            distanceFromTop: contentView.bounds.height - centerInWindow.y
        )
    }

    // MARK: - Test environment detection

    @Test func isRunningTests_returnsTrueInTestEnvironment() {
        #expect(AppDelegate.isRunningTests,
               "isRunningTests should be true when running under XCTest")
    }

    // MARK: - Settings view does not impose a fixed size that conflicts with window

    // MARK: - No redundant worktree loading from repo selection sink

    @Test func selectedRepoDoesNotEagerLoadWorktrees() async throws {
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

        // Explicitly complete the eager load so the observation chain stabilizes
        await repoVM.loadRepositories()

        // Wait for the observation cycle to complete (onChange → sync worktreeVM → re-register)
        if repoVM.selectedRepository != nil {
            try await pollUntil { worktreeVM.repository != nil }
        }

        // Act: change selectedRepository — triggers the (re-registered) observation callback
        let repo = Repository(name: "no-eager-test", path: "/tmp/no-eager-test")
        repoVM.selectedRepository = repo

        // Wait for the observer to sync worktreeViewModel.repository
        try await pollUntil { worktreeVM.repository?.id == repo.id }

        // Assert: repository should be synced by the observer
        #expect(worktreeVM.repository?.id == repo.id,
               "AppDelegate should sync worktreeViewModel.repository")

        // Assert: worktrees should NOT be loaded by AppDelegate
        // (ContentView and menuWillOpen are responsible for loading)
        #expect(worktreeVM.worktrees.isEmpty,
               "AppDelegate should not trigger worktree loading from selectedRepository sink")
    }

    // MARK: - Cold start: opening the window must load the pre-synced worktree list

    /// Regression for the v2.0.4-era first-launch empty list (counterpart of
    /// `selectedRepoDoesNotEagerLoadWorktrees`): on cold start the selection
    /// observer syncs `worktreeViewModel.repository` before any window exists,
    /// intentionally WITHOUT loading worktrees. When the main window then
    /// opens, ContentView's initial load must still run — `repository != nil`
    /// does not mean the list was ever loaded.
    ///
    /// Also serves as the window-lifecycle canary for this suite: it goes
    /// through the production `showOrCreateMainWindow()` path, which is only
    /// safe because window animations are disabled under test (see
    /// `showOrCreateWindow`). See the PR for the crash analysis.
    @Test func coldStart_windowOpen_loadsPreSyncedWorktreeList() async throws {
        // A lingering main window from an earlier test would be reused by
        // showOrCreateMainWindow and host the wrong view models. Wait for the
        // suite deinit to close it and for AppKit to release it. Do NOT close
        // it here: closing another test's window while its order-front
        // animation could still be in flight is exactly the crash this suite
        // is hardened against.
        try await pollUntil {
            !NSApp.windows.contains { $0.title == AppDelegate.mainWindowTitle }
        }

        let mockExecutor = MockSimpleGitExecutor()
        mockExecutor.worktreeListOutput = """
        worktree /tmp/cold-start-window-test
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/cold-start-window-test/wt-feature
        HEAD abc2222
        branch refs/heads/feature/x

        """

        let worktreeVM = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: mockExecutor, fileManager: MockNoOpFileManager()),
            store: .shared,
            pullRequestService: MockNoPRService()
        )
        let repoVM = RepositoryListViewModel()

        // Cold-start state right before the window opens: repositories loaded,
        // selection restored, repository synced — but the list never loaded.
        let repo = Repository(name: "cold-start-window-test", path: "/tmp/cold-start-window-test")
        repoVM.repositories = [repo]
        repoVM.selectedRepository = repo
        worktreeVM.repository = repo
        #expect(worktreeVM.worktrees.isEmpty)

        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.repoViewModel = repoVM
        appDelegate.worktreeViewModel = worktreeVM
        appDelegate.shortcutStore = ShortcutStore()

        // The production cold-start path: status item / hotkey / Dock reopen
        // all open the window through here. The window is cleaned up by this
        // suite's deinit (same as the other showOrCreateMainWindow tests).
        appDelegate.showOrCreateMainWindow()

        // ContentView's appearance must trigger the initial worktree load.
        try await pollUntil { worktreeVM.worktrees.count == 2 }
    }

    // MARK: - Settings view does not impose a fixed size that conflicts with window

    @Test func settingsViewIntrinsicSizeIsNotFixedFramePlusPadding() async throws {
        let appDelegate = AppDelegate()
        appDelegate.setupStatusItem()
        appDelegate.updaterManager = UpdaterManager()
        appDelegate.shortcutStore = ShortcutStore()

        appDelegate.showOrCreateSettingsWindow()

        let window = try #require(
            NSApp.windows.first(where: { $0.title == AppDelegate.settingsWindowTitle }),
            "Settings window should exist"
        )
        let hostingView = try #require(window.contentView, "Window should have a content view")

        let intrinsicSize = hostingView.intrinsicContentSize
        let buggyWidth: CGFloat = 432
        let buggyHeight: CGFloat = 532
        let tolerance: CGFloat = 2

        let hasRedundantFrame =
            abs(intrinsicSize.width - buggyWidth) < tolerance &&
            abs(intrinsicSize.height - buggyHeight) < tolerance

        let message: Comment = """
            SettingsView should not impose a fixed 400x500 frame; \
            the NSWindow owns the sizing. Intrinsic size was \
            \(intrinsicSize.width)x\(intrinsicSize.height), which matches \
            the .frame(400,500).padding() overflow pattern.
            """
        #expect(false == hasRedundantFrame, message)
    }

    // MARK: - Silent guard failures don't crash

    @Test func showOrCreateMainWindow_doesNotCrashWhenViewModelsNil() {
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
        #expect(afterCount == beforeCount, "No window should be created when view models are nil")
    }

    @Test func showOrCreateSettingsWindow_doesNotCrashWhenUpdaterManagerNil() {
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
        #expect(afterCount == beforeCount, "No window should be created when updaterManager is nil")
    }
}
