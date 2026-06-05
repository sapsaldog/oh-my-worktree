import AppKit
import Combine
import KeyboardShortcuts
import Observation
import os
import SwiftUI

let appDelegateLogger = Logger(subsystem: "com.ohmyworktree", category: "AppDelegate")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Constants

    static let mainWindowTitle = "Oh My Worktree"
    static let settingsWindowTitle = "OhMyWorktree Settings"

    /// `true` when the process is hosted by XCTest (unit-test runs).
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    // MARK: - Properties

    var statusItem: NSStatusItem?
    var repoViewModel: RepositoryListViewModel? {
        didSet {
            guard repoViewModel !== oldValue else { return }
            observeRepositoryChanges()
        }
    }
    var worktreeViewModel: WorktreeListViewModel? {
        didSet {
            guard worktreeViewModel !== oldValue else { return }
            observeWorktreeChanges()
        }
    }
    var updaterManager: UpdaterManager?
    var shortcutStore: ShortcutStore?

    var menuRefreshTask: Task<Void, Never>?
    var cancellables = Set<AnyCancellable>()
    private let headMonitor = GitHeadMonitor()
    private let windowObserver = WindowObserver()
    var liveBranchName: String?
    /// Retains the main window's toolbar delegate (NSToolbar holds it weakly).
    var mainToolbarDelegate: MainToolbarDelegate?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = AppearanceMode.named(
            UserDefaults.standard.string(forKey: "appearanceMode")
        ).nsAppearance
        setupStatusItem()

        if !Self.isRunningTests {
            windowObserver.startObserving()
            registerGlobalHotkeyHandler()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showOrCreateMainWindow()
        }
        return true
    }

    // MARK: - Observe ViewModel Changes

    private func observeRepositoryChanges() {
        guard let repoViewModel else { return }

        if repoViewModel.repositories.isEmpty {
            Task {
                await repoViewModel.loadRepositories()
            }
        }

        observeRepositories()
        observeSelectedRepository()
    }

    private func observeRepositories() {
        guard let repoViewModel else { return }
        withObservationTracking {
            _ = repoViewModel.repositories
        } onChange: {
            Task { @MainActor [weak self] in
                self?.rebuildMenu()
                self?.updateStatusItemTitle()
                self?.observeRepositories()
            }
        }
    }

    private func observeSelectedRepository() {
        guard let repoViewModel else { return }
        withObservationTracking {
            _ = repoViewModel.selectedRepository
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.worktreeViewModel?.repository = self.repoViewModel?.selectedRepository
                self.rebuildMenu()
                self.updateStatusItemTitle()
                self.observeSelectedRepository()
            }
        }
    }

    private func observeWorktreeChanges() {
        cancellables.removeAll()

        guard worktreeViewModel != nil else {
            headMonitor.stopMonitoring()
            liveBranchName = nil
            return
        }

        headMonitor.onBranchChange = { [weak self] branch in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.liveBranchName = branch
                self.updateStatusItemTitle()
                if let worktree = self.worktreeViewModel?.selectedWorktree {
                    await self.worktreeViewModel?.recordActivity(for: worktree)
                }
            }
        }

        worktreeViewModel?.selectedWorktreeSubject
            .sink { [weak self] worktree in
                guard let self else { return }
                self.liveBranchName = nil
                self.updateStatusItemTitle()
                if let worktree {
                    self.headMonitor.startMonitoring(worktreePath: worktree.path)
                } else {
                    self.headMonitor.stopMonitoring()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Status Item Setup

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(
                    systemSymbolName: "arrow.triangle.branch",
                    accessibilityDescription: "Oh My Worktree"
                )
            }
            button.imagePosition = .imageLeading
            button.title = " Oh My Worktree"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    // MARK: - Global Hotkey Setup

    /// Registers the global hotkey handler once. The library keeps tracking the
    /// shortcut even after the user changes it via the recorder.
    func registerGlobalHotkeyHandler() {
        KeyboardShortcuts.onKeyDown(for: .toggleMenuBarPopup) { [weak self] in
            self?.showOrCreateMainWindow()
        }
    }

    /// Enables or disables the global hotkey based on the persisted toggle.
    func setupGlobalHotkey() {
        let enabled = UserDefaults.standard.object(forKey: "globalHotkeyEnabled") as? Bool ?? true
        if enabled {
            KeyboardShortcuts.enable(.toggleMenuBarPopup)
        } else {
            KeyboardShortcuts.disable(.toggleMenuBarPopup)
        }
    }

    // MARK: - Update Title

    func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }

        if let repo = repoViewModel?.selectedRepository {
            if let worktree = worktreeViewModel?.selectedWorktree {
                let branchDisplay = worktree.customName ?? liveBranchName ?? worktree.displayName
                button.title = " \(repo.name)/\(branchDisplay)"
            } else {
                button.title = " \(repo.name)"
            }
        } else {
            button.title = " Oh My Worktree"
        }
    }
}
