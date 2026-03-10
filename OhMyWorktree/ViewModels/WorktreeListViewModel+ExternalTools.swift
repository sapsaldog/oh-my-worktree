import AppKit
import Foundation

extension WorktreeListViewModel {
    // MARK: - Open in External Tools

    func openInITerm(_ worktree: Worktree? = nil, mode: AppSettings.OpenMode = .newTab) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }
        do {
            try await toolLauncher.openInITerm(path: target.path, mode: mode)
            await recordActivity(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInGhostty(_ worktree: Worktree? = nil) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }
        do {
            try await toolLauncher.openInGhostty(path: target.path)
            await recordActivity(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInVSCode(
        _ worktree: Worktree? = nil,
        mode: AppSettings.OpenMode = .newWindow
    ) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }
        do {
            try await toolLauncher.openInVSCode(path: target.path, mode: mode)
            await recordActivity(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInCursor(_ worktree: Worktree? = nil) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }
        do {
            try await toolLauncher.openInCursor(path: target.path)
            await recordActivity(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInCmux(_ worktree: Worktree? = nil) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }
        do {
            try await toolLauncher.openInCmux(path: target.path)
            await recordActivity(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recordActivity(for worktree: Worktree) async {
        guard let repository else { return }
        await store.updateLastActivity(
            folderName: worktree.folderName,
            repositoryID: repository.id
        )
        if let index = worktrees.firstIndex(where: { $0.id == worktree.id }) {
            worktrees[index].lastActivityAt = Date()
        }
    }

    // MARK: - Tool Availability

    var isITermAvailable: Bool { toolLauncher.isITermInstalled() }
    var isGhosttyAvailable: Bool { toolLauncher.isGhosttyInstalled() }
    var isVSCodeAvailable: Bool { toolLauncher.isVSCodeInstalled() }
    var isCursorAvailable: Bool { toolLauncher.isCursorInstalled() }
    var isCmuxAvailable: Bool { toolLauncher.isCmuxInstalled() }
}
