import AppKit
import Combine
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - Properties

    var statusItem: NSStatusItem?
    var repoViewModel: RepositoryListViewModel?
    var worktreeViewModel: WorktreeListViewModel? {
        didSet {
            guard worktreeViewModel !== oldValue else { return }
            observeWorktreeChanges()
        }
    }
    var openMainWindow: (() -> Void)?
    var openSettings: (() -> Void)?
    var updaterManager: UpdaterManager?
    private var menuRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let headMonitor = GitHeadMonitor()
    private var liveBranchName: String?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
    }

    // MARK: - Observe ViewModel Changes

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

        worktreeViewModel?.$selectedWorktree
            .receive(on: RunLoop.main)
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
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Oh My Worktree")
            button.imagePosition = .imageLeading
            button.title = "Oh My Worktree"
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
                let branchDisplay = liveBranchName ?? worktree.displayName
                button.title = "\(repo.name)/\(branchDisplay)"
            } else {
                button.title = repo.name
            }
        } else {
            button.title = "Oh My Worktree"
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        // Cancel any previous refresh to avoid stacking
        menuRefreshTask?.cancel()
        menuRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
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

        let repositories = repoViewModel?.repositories ?? []
        let selectedRepo = repoViewModel?.selectedRepository
        let worktrees = worktreeViewModel?.worktrees ?? []

        // --- Repository Section ---

        for repo in repositories {
            let item = NSMenuItem(
                title: repo.name,
                action: #selector(repositorySelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = repo.id
            if let selectedRepo, selectedRepo.id == repo.id {
                item.state = .on
            }
            menu.addItem(item)
        }

        if !repositories.isEmpty {
            menu.addItem(.separator())
        }

        // --- Worktree Section ---

        for worktree in worktrees {
            if worktree.isBare { continue }

            let bullet = (worktreeViewModel?.selectedWorktree?.id == worktree.id) ? "\u{25CF} " : "   "
            let activity = worktree.relativeLastActivity.map { "  \($0)" } ?? ""
            let title = "\(bullet)\(worktree.displayName)\(activity)"

            let item = NSMenuItem(
                title: title,
                action: #selector(worktreeSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = WorktreeRef(id: worktree.id, path: worktree.path)

            // Build submenu for external tools
            let submenu = buildWorktreeSubmenu(for: worktree)
            item.submenu = submenu

            menu.addItem(item)
        }

        if !worktrees.isEmpty || !repositories.isEmpty {
            menu.addItem(.separator())
        }

        // --- New Worktree ---

        let addItem = NSMenuItem(
            title: "+ New Worktree",
            action: #selector(newWorktreeClicked(_:)),
            keyEquivalent: "n"
        )
        addItem.target = self
        addItem.isEnabled = (repoViewModel?.selectedRepository != nil)
        menu.addItem(addItem)

        menu.addItem(.separator())

        // --- Open Main Window ---

        let openWindowItem = NSMenuItem(
            title: "Open Main Window",
            action: #selector(openMainWindowClicked(_:)),
            keyEquivalent: "o"
        )
        openWindowItem.target = self
        menu.addItem(openWindowItem)

        // --- Settings ---

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(settingsClicked(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesClicked(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        checkForUpdatesItem.isEnabled = updaterManager?.canCheckForUpdates ?? false
        menu.addItem(checkForUpdatesItem)

        menu.addItem(.separator())

        // --- Quit ---

        let quitItem = NSMenuItem(
            title: "Quit Oh My Worktree",
            action: #selector(quitClicked(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Worktree Submenu

    private func buildWorktreeSubmenu(for worktree: Worktree) -> NSMenu {
        let submenu = NSMenu()
        let ref = WorktreeRef(id: worktree.id, path: worktree.path)

        if worktreeViewModel?.isITermAvailable == true {
            let item = NSMenuItem(
                title: "Open in iTerm",
                action: #selector(openInITermClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = ref
            submenu.addItem(item)
        }

        if worktreeViewModel?.isGhosttyAvailable == true {
            let item = NSMenuItem(
                title: "Open in Ghostty",
                action: #selector(openInGhosttyClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = ref
            submenu.addItem(item)
        }

        if worktreeViewModel?.isVSCodeAvailable == true {
            let item = NSMenuItem(
                title: "Open in VSCode",
                action: #selector(openInVSCodeClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = ref
            submenu.addItem(item)
        }

        if worktreeViewModel?.isCursorAvailable == true {
            let item = NSMenuItem(
                title: "Open in Cursor",
                action: #selector(openInCursorClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = ref
            submenu.addItem(item)
        }

        if submenu.numberOfItems > 0 {
            submenu.addItem(.separator())
        }

        // Git Pull — only for root worktree
        if let repository = repoViewModel?.selectedRepository, worktree.isRoot(of: repository) {
            let pullItem = NSMenuItem(
                title: "Git Pull",
                action: #selector(gitPullClicked(_:)),
                keyEquivalent: ""
            )
            pullItem.target = self
            pullItem.representedObject = ref
            submenu.addItem(pullItem)
            submenu.addItem(.separator())
        }

        let copyItem = NSMenuItem(
            title: "Copy Path",
            action: #selector(copyPathClicked(_:)),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyItem.representedObject = ref
        submenu.addItem(copyItem)

        let finderItem = NSMenuItem(
            title: "Show in Finder",
            action: #selector(showInFinderClicked(_:)),
            keyEquivalent: ""
        )
        finderItem.target = self
        finderItem.representedObject = ref
        submenu.addItem(finderItem)

        return submenu
    }

    // MARK: - Helpers

    private func showOrCreateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // Try to show an existing window first
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            return
        }

        // No existing window - create a new one
        openMainWindow?()
    }

    // MARK: - Actions: Repository

    @objc private func repositorySelected(_ sender: NSMenuItem) {
        guard let repoID = sender.representedObject as? UUID,
              let repo = repoViewModel?.repositories.first(where: { $0.id == repoID })
        else { return }

        // Show main window to display the worktree list
        showOrCreateMainWindow()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.repoViewModel?.selectRepository(repo)
            self.worktreeViewModel?.repository = repo
            await self.worktreeViewModel?.loadWorktrees()
            self.updateStatusItemTitle()
        }
    }

    // MARK: - Actions: Worktree Selection

    @objc private func worktreeSelected(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.worktreeViewModel?.selectedWorktree = self.worktreeViewModel?.worktrees.first(where: { $0.id == ref.id })
            self.updateStatusItemTitle()
        }
    }

    // MARK: - Actions: External Tools

    @objc private func openInITermClicked(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let worktree = self.worktreeViewModel?.worktrees.first(where: { $0.id == ref.id })
            await self.worktreeViewModel?.openInITerm(worktree)
        }
    }

    @objc private func openInGhosttyClicked(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let worktree = self.worktreeViewModel?.worktrees.first(where: { $0.id == ref.id })
            await self.worktreeViewModel?.openInGhostty(worktree)
        }
    }

    @objc private func openInVSCodeClicked(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let worktree = self.worktreeViewModel?.worktrees.first(where: { $0.id == ref.id })
            await self.worktreeViewModel?.openInVSCode(worktree)
        }
    }

    @objc private func openInCursorClicked(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let worktree = self.worktreeViewModel?.worktrees.first(where: { $0.id == ref.id })
            await self.worktreeViewModel?.openInCursor(worktree)
        }
    }

    // MARK: - Actions: Path & Finder

    @objc private func copyPathClicked(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ref.path, forType: .string)
    }

    @objc private func showInFinderClicked(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef else { return }

        let url = URL(fileURLWithPath: ref.path)
        NSWorkspace.shared.open(url)
    }

    @objc private func gitPullClicked(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef else { return }

        // Show main window to display the result alert
        showOrCreateMainWindow()

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let worktree = self.worktreeViewModel?.worktrees.first(where: { $0.id == ref.id }) {
                await self.worktreeViewModel?.gitPull(worktree)
                // ContentView alert will show the result
            }
        }
    }

    // MARK: - Actions: New Worktree

    @objc private func newWorktreeClicked(_ sender: NSMenuItem) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.worktreeViewModel?.addWorktree()
            self.updateStatusItemTitle()
        }
    }

    // MARK: - Actions: Open Main Window

    @objc private func openMainWindowClicked(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)

        // Try to show an existing window first
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            return
        }

        // No existing window - create a new one via SwiftUI
        openMainWindow?()
    }

    // MARK: - Actions: Settings

    @objc private func settingsClicked(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        openSettings?()
    }

    // MARK: - Actions: Check for Updates

    @objc private func checkForUpdatesClicked(_ sender: NSMenuItem) {
        updaterManager?.checkForUpdates()
    }

    // MARK: - Actions: Quit

    @objc private func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - WorktreeRef

/// Lightweight reference type used as `representedObject` on NSMenuItems
/// to identify which worktree a menu action targets.
private final class WorktreeRef: NSObject {
    let id: UUID
    let path: String

    init(id: UUID, path: String) {
        self.id = id
        self.path = path
        super.init()
    }
}

