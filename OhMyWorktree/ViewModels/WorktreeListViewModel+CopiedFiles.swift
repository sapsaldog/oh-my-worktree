import Foundation

// MARK: - Copied-files browser glue
//
// Thin view-model glue for the copied-files browser. Diffs are computed by the
// tested `CopiedFileDiffer`; opening a file hands off to an external diff tool
// (see `openInDiffTool` in WorktreeListViewModel+ExternalTools).

extension WorktreeListViewModel {

    /// Open state for the copied-files browser sheet.
    struct CopiedBrowserState: Equatable {
        var worktree: Worktree
    }

    /// Opens the browser to the full list for `worktree`.
    func browseCopiedFiles(for worktree: Worktree) {
        copiedBrowser = CopiedBrowserState(worktree: worktree)
    }
}
