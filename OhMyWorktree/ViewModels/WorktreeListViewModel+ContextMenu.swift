import Foundation

// MARK: - ContextMenuActions

struct ContextMenuActions {
    let canOpen: Bool
    let canRename: Bool
    let canGitPull: Bool
    let canRemove: Bool
    let canForceRemove: Bool
    let canShowInFinder: Bool
    let canCopyPath: Bool
}

extension WorktreeListViewModel {
    func contextMenuActions(for worktree: Worktree) -> ContextMenuActions {
        let isMultiSelected = selectedWorktreeIDs.count >= 2
            && selectedWorktreeIDs.contains(worktree.id)

        if isMultiSelected {
            let allRemovable = !worktrees.contains { w in
                selectedWorktreeIDs.contains(w.id)
                    && ((repository.map { w.isRoot(of: $0) } ?? false) || w.isBare)
            }
            let hasRemovableTarget = allRemovable && worktrees.contains { w in
                selectedWorktreeIDs.contains(w.id)
                    && !jobQueue.busyWorktreeIDs.contains(w.id)
            }
            return ContextMenuActions(
                canOpen: false,
                canRename: false,
                canGitPull: false,
                canRemove: hasRemovableTarget,
                canForceRemove: hasRemovableTarget,
                canShowInFinder: false,
                canCopyPath: false
            )
        }

        // Single-item behavior
        let isBusy = jobQueue.busyWorktreeIDs.contains(worktree.id)
        let isRoot = repository.map { worktree.isRoot(of: $0) } ?? false
        let canRemove = !isRoot && !worktree.isBare && !isBusy
        return ContextMenuActions(
            canOpen: !isBusy,
            canRename: !isBusy,
            canGitPull: !worktree.isBare && !isBusy,
            canRemove: canRemove,
            canForceRemove: canRemove,
            canShowInFinder: true,
            canCopyPath: true
        )
    }
}
