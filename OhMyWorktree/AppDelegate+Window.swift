import AppKit
import SwiftUI

// MARK: - Window Management

extension AppDelegate {

    /// Shows an existing window with the given title, or creates a new one.
    func showOrCreateWindow(
        title: String,
        size: NSSize,
        styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable],
        configure: ((NSWindow) -> Void)? = nil,
        onShow: ((NSWindow) -> Void)? = nil,
        rootView: () -> some View
    ) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        for window in NSApp.windows where window.title == title {
            window.makeKeyAndOrderFront(nil)
            if window.isMiniaturized { window.deminiaturize(nil) }
            onShow?(window)
            return
        }

        let window = NSWindow(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // Use a hosting *controller* (not a bare NSHostingView) so SwiftUI is
        // constrained to the window's content bounds and lays out correctly on
        // first show. A bare NSHostingView offers an unconstrained width on the
        // initial pass, which makes the flexible column overflow the window.
        window.contentViewController = NSHostingController(rootView: rootView())
        window.title = title
        configure?(window)
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        onShow?(window)
    }

    func showOrCreateMainWindow() {
        appDelegateLogger.info("showOrCreateMainWindow called")
        guard let repoVM = repoViewModel,
              let worktreeVM = worktreeViewModel else {
            appDelegateLogger.warning("showOrCreateMainWindow: view models not connected")
            return
        }

        guard let store = shortcutStore else {
            appDelegateLogger.warning("showOrCreateMainWindow: shortcutStore not connected")
            return
        }
        showOrCreateWindow(
            title: Self.mainWindowTitle,
            size: NSSize(width: 1180, height: 740),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            configure: { window in
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
                window.minSize = NSSize(width: 860, height: 520)
                window.tabbingMode = .disallowed
                // A native unified toolbar hosts the controls and lets macOS
                // vertically center the traffic lights for us.
                let delegate = MainToolbarDelegate(worktreeVM: worktreeVM)
                self.mainToolbarDelegate = delegate
                let toolbar = NSToolbar(identifier: "OMWMainToolbar")
                toolbar.delegate = delegate
                toolbar.showsBaselineSeparator = false
                window.toolbar = toolbar
                window.toolbarStyle = .unified
            }
        ) {
            ContentView(repoViewModel: repoVM, worktreeViewModel: worktreeVM)
                .environment(store)
                .frame(minWidth: 860, minHeight: 520)
        }
    }

    @objc func showOrCreateSettingsWindow() {
        guard let updaterManager else { return }
        guard let shortcutStore else { return }

        showOrCreateWindow(
            title: Self.settingsWindowTitle,
            size: NSSize(width: 500, height: 450),
            styleMask: [.titled, .closable]
        ) {
            SettingsView(updaterManager: updaterManager, store: shortcutStore)
        }
    }
}

// MARK: - Main window toolbar

/// Provides the main window's native unified toolbar items: a real
/// `NSSearchToolbarItem` plus standard button items. Native items size
/// themselves and pick up the system's Liquid Glass treatment, and the unified
/// style vertically centers the traffic lights. A flexible space right-aligns
/// the cluster, matching the prototype.
@MainActor
final class MainToolbarDelegate: NSObject, NSToolbarDelegate {
    private let worktreeVM: WorktreeListViewModel

    private static let search = NSToolbarItem.Identifier("OMWSearch")
    private static let importPR = NSToolbarItem.Identifier("OMWImportPR")
    private static let refresh = NSToolbarItem.Identifier("OMWRefresh")
    private static let settings = NSToolbarItem.Identifier("OMWSettings")
    private static let newWorktree = NSToolbarItem.Identifier("OMWNewWorktree")

    init(worktreeVM: WorktreeListViewModel) {
        self.worktreeVM = worktreeVM
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.search, Self.importPR, Self.refresh, Self.settings, Self.newWorktree]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.search:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.searchField.placeholderString = "Filter worktrees…"
            item.searchField.target = self
            item.searchField.action = #selector(searchChanged(_:))
            return item
        case Self.importPR:
            return button(itemIdentifier, asset: "GitHubMark",
                          label: "Import from Pull Request", action: #selector(importTapped))
        case Self.refresh:
            return button(itemIdentifier, symbol: "arrow.clockwise",
                          label: "Refresh", action: #selector(refreshTapped))
        case Self.settings:
            return button(itemIdentifier, symbol: "gearshape",
                          label: "Settings", action: #selector(settingsTapped))
        case Self.newWorktree:
            return button(itemIdentifier, symbol: "plus",
                          label: "New Worktree", action: #selector(newTapped))
        default:
            return nil
        }
    }

    private func button(_ id: NSToolbarItem.Identifier, symbol: String? = nil, asset: String? = nil,
                        label: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.toolTip = label
        item.isBordered = true
        item.target = self
        item.action = action
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        } else if let asset, let image = NSImage(named: asset) {
            image.isTemplate = true
            item.image = image
        }
        return item
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        worktreeVM.searchText = sender.stringValue
    }
    @objc private func importTapped() { worktreeVM.isShowingImportPR = true }
    @objc private func refreshTapped() { Task { await worktreeVM.loadWorktrees() } }
    @objc private func settingsTapped() { worktreeVM.isShowingSettings = true }
    @objc private func newTapped() { worktreeVM.isShowingCreateSheet = true }
}
