import AppKit
import Foundation

extension WorktreeListViewModel {
    // MARK: - Open in External Tools

    /// Unified helper that resolves the target worktree, opens it with the given launcher closure,
    /// records activity, and surfaces any error to the UI.
    private func openInTool(
        _ worktree: Worktree?,
        launch: (String) async throws -> Void
    ) async {
        let target = worktree ?? selectedWorktree
        guard let target else { return }
        do {
            try await launch(target.path)
            await recordActivity(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInITerm(_ worktree: Worktree? = nil, mode: AppSettings.OpenMode = .newTab) async {
        await openInTool(worktree) { path in
            try await toolLauncher.openInITerm(path: path, mode: mode)
        }
    }

    func openInGhostty(_ worktree: Worktree? = nil) async {
        await openInTool(worktree) { path in
            try await toolLauncher.openInGhostty(path: path)
        }
    }

    func openInVSCode(
        _ worktree: Worktree? = nil,
        mode: AppSettings.OpenMode = .newWindow
    ) async {
        await openInTool(worktree) { path in
            try await toolLauncher.openInVSCode(path: path, mode: mode)
        }
    }

    func openInCursor(_ worktree: Worktree? = nil) async {
        await openInTool(worktree) { path in
            try await toolLauncher.openInCursor(path: path)
        }
    }

    func openInCmux(_ worktree: Worktree? = nil) async {
        await openInTool(worktree) { path in
            try await toolLauncher.openInCmux(path: path)
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
