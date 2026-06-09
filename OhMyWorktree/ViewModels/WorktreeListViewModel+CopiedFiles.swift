import Foundation

// MARK: - Copied-files browser + apply-to-main glue
//
// Thin view-model glue: opening/closing the browser, drilling into a file, and
// applying a copy back to main. The real work (diff + atomic write) lives in the
// tested `CopiedFileDiffer`; this layer only coordinates state and reloads detail.

extension WorktreeListViewModel {

    /// Open state for the copied-files browser sheet.
    struct CopiedBrowserState: Equatable {
        var worktree: Worktree
        var focusedPath: String?
    }

    /// Opens the browser to the full list for `worktree`.
    func browseCopiedFiles(for worktree: Worktree) {
        copiedBrowser = CopiedBrowserState(worktree: worktree, focusedPath: nil)
    }

    /// Opens the browser straight to `file`'s diff for `worktree`.
    func openCopiedDiff(_ file: CopiedFile, for worktree: Worktree) {
        copiedBrowser = CopiedBrowserState(worktree: worktree, focusedPath: file.path)
    }

    /// Applies `file` (worktree → main), reloads the detail so statuses refresh,
    /// and shows a toast. Surfaces failures through the standard error alert.
    func applyCopiedFileToMain(_ file: CopiedFile, in worktree: Worktree) async {
        guard let repository else { return }
        let differ = self.differ
        let worktreePath = worktree.path
        let repoPath = repository.path
        do {
            try await Task.detached {
                try differ.applyToMain(file, worktreePath: worktreePath, repositoryPath: repoPath)
            }.value
            await loadDetail(for: worktree)
            copiedBrowser?.focusedPath = nil
            copiedToast = "Applied \((file.path as NSString).lastPathComponent) to main"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
