import AppKit
import Combine

// MARK: - WorktreeRef

/// Lightweight reference type used as `representedObject` on NSMenuItems
/// to identify which worktree a menu action targets.
/// Internal (not private) so it can be referenced across AppDelegate and AppDelegate+Actions files.
internal final class WorktreeRef: NSObject {
    let id: UUID
    let path: String
    let prURL: URL?

    init(id: UUID, path: String, prURL: URL? = nil) {
        self.id = id
        self.path = path
        self.prURL = prURL
        super.init()
    }
}

// MARK: - Repository & Worktree Selection Actions

extension AppDelegate {

    @objc func repositorySelected(_ sender: NSMenuItem) {
        guard let repoID = sender.representedObject as? UUID,
              let repo = repoViewModel?.repositories.first(where: { $0.id == repoID })
        else { return }

        showOrCreateMainWindow()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.repoViewModel?.selectRepository(repo)
            self.worktreeViewModel?.repository = repo
            await self.worktreeViewModel?.loadWorktrees()
            self.updateStatusItemTitle()
        }
    }

    @objc func worktreeSelected(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef,
              let worktree = worktreeViewModel?.worktrees.first(where: { $0.id == ref.id })
        else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.worktreeViewModel?.selectedWorktree = worktree
            self.updateStatusItemTitle()
        }
    }
}

// MARK: - External Tool Actions

extension AppDelegate {

    @objc func openInITermClicked(_ sender: NSMenuItem) {
        openWorktree(sender) { vm, worktree in await vm.openInITerm(worktree) }
    }

    @objc func openInGhosttyClicked(_ sender: NSMenuItem) {
        openWorktree(sender) { vm, worktree in await vm.openInGhostty(worktree) }
    }

    @objc func openInVSCodeClicked(_ sender: NSMenuItem) {
        openWorktree(sender) { vm, worktree in await vm.openInVSCode(worktree) }
    }

    @objc func openInCursorClicked(_ sender: NSMenuItem) {
        openWorktree(sender) { vm, worktree in await vm.openInCursor(worktree) }
    }

    @objc func openInCmuxClicked(_ sender: NSMenuItem) {
        openWorktree(sender) { vm, worktree in await vm.openInCmux(worktree) }
    }

    /// Resolves the target worktree from `sender.representedObject` at call time (before Task creation)
    /// to avoid stale lookups inside the async context.
    private func openWorktree(
        _ sender: NSMenuItem,
        action: @escaping @MainActor (WorktreeListViewModel, Worktree) async -> Void
    ) {
        guard let ref = sender.representedObject as? WorktreeRef,
              let vm = worktreeViewModel,
              let worktree = vm.worktrees.first(where: { $0.id == ref.id })
        else { return }
        Task { await action(vm, worktree) }
    }
}

// MARK: - Path, Finder & Pull Actions

extension AppDelegate {

    @objc func copyPathClicked(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ref.path, forType: .string)
    }

    @objc func showInFinderClicked(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: ref.path))
    }

    @objc func gitPullClicked(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef,
              let worktree = worktreeViewModel?.worktrees.first(where: { $0.id == ref.id })
        else { return }
        worktreeViewModel?.gitPull(worktree)
    }

    @objc func openPullRequestClicked(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeRef,
              let url = ref.prURL
        else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Window & App Actions

extension AppDelegate {

    @objc func newWorktreeClicked(_ sender: NSMenuItem) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.worktreeViewModel?.addWorktree()
            self.updateStatusItemTitle()
        }
    }

    @objc func openMainWindowClicked(_ sender: NSMenuItem) {
        showOrCreateMainWindow()
    }

    @objc func importFromGitHubPRClicked(_ sender: NSMenuItem) {
        showOrCreateMainWindow()
        DispatchQueue.main.async { [weak self] in
            self?.worktreeViewModel?.isShowingImportPR = true
        }
    }

    @objc func settingsClicked(_ sender: NSMenuItem) {
        showOrCreateSettingsWindow()
    }

    @objc func checkForUpdatesClicked(_ sender: NSMenuItem) {
        updaterManager?.checkForUpdates()
    }

    @objc func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Shortcut Manager Observation

extension AppDelegate {

    func observeShortcutChanges() {
        shortcutManager?.$version
            .dropFirst()
            .sink { [weak self] _ in
                self?.setupGlobalHotkey()
            }
            .store(in: &cancellables)
    }
}
