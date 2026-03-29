import AppKit
import Combine
import os
import SwiftUI

private let appDelegateLogger = Logger(subsystem: "com.ohmyworktree", category: "AppDelegate")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

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

    private var menuRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var repoCancellables = Set<AnyCancellable>()
    private let headMonitor = GitHeadMonitor()
    private let windowObserver = WindowObserver()
    private var liveBranchName: String?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        // Skip WindowObserver during tests — each test-created window would
        // trigger .regular activation policy, spawning Dock icons that pile up
        // across repeated xcodebuild runs.
        if !Self.isRunningTests {
            windowObserver.startObserving()
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
        repoCancellables.removeAll()

        guard let repoViewModel else { return }

        // Eagerly load repositories so the menu bar is populated
        // even before the main window appears (fixes cold-start on reboot).
        if repoViewModel.repositories.isEmpty {
            Task {
                await repoViewModel.loadRepositories()
            }
        }

        // Rebuild menu whenever the repository list or selection changes.
        repoViewModel.$repositories
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebuildMenu()
                self?.updateStatusItemTitle()
            }
            .store(in: &repoCancellables)

        repoViewModel.$selectedRepository
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self else { return }
                // Sync worktreeViewModel so menu bar and windows show worktrees.
                // Worktree loading is handled by ContentView (.onChange) and
                // menuWillOpen — no need to duplicate it here.
                self.worktreeViewModel?.repository = newValue
                self.rebuildMenu()
                self.updateStatusItemTitle()
            }
            .store(in: &repoCancellables)
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
                button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Oh My Worktree")
            }
            button.imagePosition = .imageLeading
            button.title = " Oh My Worktree"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
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

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        // Cancel any previous refresh to avoid stacking
        menuRefreshTask?.cancel()
        menuRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Ensure repositories are loaded (cold-start safety net)
            if self.repoViewModel?.repositories.isEmpty == true {
                await self.repoViewModel?.loadRepositories()
            }
            let before = self.worktreeViewModel?.worktrees
            await self.worktreeViewModel?.loadWorktrees(debounce: true)
            // Only rebuild if data actually changed to avoid menu flicker
            if before != self.worktreeViewModel?.worktrees {
                self.rebuildMenu()
                self.updateStatusItemTitle()
            }
        }
    }

    // MARK: - Menu Construction

    func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        addRepositorySection(to: menu)
        addWorktreeSection(to: menu)
        addSystemMenuItems(to: menu)
    }

    // MARK: - Menu Section Builders

    private func addRepositorySection(to menu: NSMenu) {
        let repositories = repoViewModel?.repositories ?? []
        let selectedRepo = repoViewModel?.selectedRepository
        for repo in repositories {
            let item = NSMenuItem(title: repo.name, action: #selector(repositorySelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = repo.id
            if let selectedRepo, selectedRepo.id == repo.id { item.state = .on }
            menu.addItem(item)
        }
        if !repositories.isEmpty { menu.addItem(.separator()) }
    }

    private func addWorktreeSection(to menu: NSMenu) {
        let worktrees = worktreeViewModel?.worktrees ?? []
        let pullRequests = worktreeViewModel?.pullRequests ?? [:]
        let deletingIDs = Set((worktreeViewModel?.jobQueue.jobs ?? [])
            .filter { job in
                job.state.isActive && {
                    switch job.kind {
                    case .removeWorktree, .quickRemove: return true
                    default: return false
                    }
                }()
            }
            .map { $0.worktreeID })

        for worktree in worktrees {
            guard !worktree.isBare else { continue }
            if deletingIDs.contains(worktree.id) { continue }
            let isSelected = worktreeViewModel?.selectedWorktree?.id == worktree.id
            let bullet = isSelected ? "\u{25CF} " : "   "
            let pr = worktree.branch.flatMap { pullRequests[$0] }
                ?? worktree.prRemoteBranch.flatMap { pullRequests[$0] }
            let prLabel = pr.map { " #\($0.number)" } ?? ""
            let activity = worktree.relativeLastActivity.map { "  \($0)" } ?? ""
            let item = NSMenuItem(
                title: "\(bullet)\(worktree.displayName)\(prLabel)\(activity)",
                action: #selector(worktreeSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = WorktreeRef(id: worktree.id, path: worktree.path, prURL: pr?.url)
            item.submenu = buildWorktreeSubmenu(for: worktree, pullRequest: pr)
            menu.addItem(item)
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
    }

    private func addSystemMenuItems(to menu: NSMenu) {
        let addItem = NSMenuItem(title: "+ New Worktree", action: #selector(newWorktreeClicked(_:)), keyEquivalent: "n")
        addItem.target = self
        addItem.isEnabled = repoViewModel?.selectedRepository != nil
        menu.addItem(addItem)

        if repoViewModel?.selectedRepository != nil && worktreeViewModel?.isGitHubRepo == true {
            let importItem = NSMenuItem(
                title: "Import from GitHub PR…",
                action: #selector(importFromGitHubPRClicked(_:)),
                keyEquivalent: ""
            )
            importItem.target = self
            menu.addItem(importItem)
        }

        menu.addItem(.separator())

        let openWindowItem = NSMenuItem(
            title: "Open Main Window", action: #selector(openMainWindowClicked(_:)), keyEquivalent: "o"
        )
        openWindowItem.target = self
        menu.addItem(openWindowItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settingsClicked(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: "Check for Updates...", action: #selector(checkForUpdatesClicked(_:)), keyEquivalent: ""
        )
        updatesItem.target = self
        updatesItem.isEnabled = updaterManager?.canCheckForUpdates ?? false
        menu.addItem(updatesItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Oh My Worktree", action: #selector(quitClicked(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Worktree Submenu

    private func buildWorktreeSubmenu(for worktree: Worktree, pullRequest: PullRequestInfo? = nil) -> NSMenu {
        let submenu = NSMenu()
        let ref = WorktreeRef(id: worktree.id, path: worktree.path)

        addExternalToolItems(to: submenu, ref: ref)

        if let pr = pullRequest {
            if submenu.numberOfItems > 0 { submenu.addItem(.separator()) }
            let prItem = NSMenuItem(
                title: "Open Pull Request #\(pr.number)", action: #selector(openPullRequestClicked(_:)), keyEquivalent: ""
            )
            prItem.target = self
            prItem.representedObject = WorktreeRef(id: worktree.id, path: worktree.path, prURL: pr.url)
            submenu.addItem(prItem)
        }

        if submenu.numberOfItems > 0 { submenu.addItem(.separator()) }

        if !worktree.isBare {
            let pullItem = NSMenuItem(title: "Git Pull", action: #selector(gitPullClicked(_:)), keyEquivalent: "")
            pullItem.target = self
            pullItem.representedObject = ref
            submenu.addItem(pullItem)
            submenu.addItem(.separator())
        }

        let copyItem = NSMenuItem(title: "Copy Path", action: #selector(copyPathClicked(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = ref
        submenu.addItem(copyItem)

        let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(showInFinderClicked(_:)), keyEquivalent: "")
        finderItem.target = self
        finderItem.representedObject = ref
        submenu.addItem(finderItem)

        return submenu
    }

    private func addExternalToolItems(to submenu: NSMenu, ref: WorktreeRef) {
        let tools: [(available: Bool, title: String, action: Selector)] = [
            (worktreeViewModel?.isITermAvailable == true, "Open in iTerm", #selector(openInITermClicked(_:))),
            (worktreeViewModel?.isGhosttyAvailable == true, "Open in Ghostty", #selector(openInGhosttyClicked(_:))),
            (worktreeViewModel?.isVSCodeAvailable == true, "Open in VSCode", #selector(openInVSCodeClicked(_:))),
            (worktreeViewModel?.isCursorAvailable == true, "Open in Cursor", #selector(openInCursorClicked(_:))),
            (worktreeViewModel?.isCmuxAvailable == true, "Open in cmux", #selector(openInCmuxClicked(_:)))
        ]
        for (available, title, action) in tools where available {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = ref
            submenu.addItem(item)
        }
    }

    // MARK: - Window Management

    /// Shows an existing window with the given title, or creates a new one.
    private func showOrCreateWindow(
        title: String,
        size: NSSize,
        styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable],
        rootView: () -> some View
    ) {
        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows where window.title == title {
            window.makeKeyAndOrderFront(nil)
            if window.isMiniaturized { window.deminiaturize(nil) }
            return
        }

        let window = NSWindow(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: rootView())
        window.title = title
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func showOrCreateMainWindow() {
        guard let repoVM = repoViewModel,
              let worktreeVM = worktreeViewModel else {
            appDelegateLogger.warning("Cannot show main window: view models not yet connected")
            return
        }

        showOrCreateWindow(
            title: Self.mainWindowTitle,
            size: NSSize(width: 500, height: 400)
        ) {
            ContentView(repoViewModel: repoVM, worktreeViewModel: worktreeVM)
                .frame(minWidth: 400, minHeight: 300)
        }
    }

    func showOrCreateSettingsWindow() {
        guard let updaterManager else {
            appDelegateLogger.warning("Cannot show settings window: updaterManager not yet connected")
            return
        }

        showOrCreateWindow(
            title: Self.settingsWindowTitle,
            size: NSSize(width: 400, height: 500),
            styleMask: [.titled, .closable]
        ) {
            SettingsView(updaterManager: updaterManager)
        }
    }

}
