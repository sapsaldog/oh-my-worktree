import Testing

@testable import OhMyWorktree

// MARK: - contextMenuActions

extension WorktreeListViewModelTests {

    // MARK: Fixtures (private to this file; rootWorktree & featureWorktree are shared)

    /// Another normal non-root worktree
    private var fixWorktree: Worktree {
        Worktree(path: "/tmp/worktrees/fix-b", folderName: "fix-b", branch: "fix/b")
    }

    /// Bare worktree — cannot be removed or pulled
    private var bareWorktree: Worktree {
        Worktree(path: "/tmp/worktrees/bare", folderName: "bare", isBare: true)
    }

    // MARK: Single-item behavior (0 or 1 selected)

    @Test func contextMenuActions_nothingSelected_nonRoot_allEnabled() {
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = []

        let actions = sut.contextMenuActions(for: featureWorktree)

        #expect(actions.canOpen)
        #expect(actions.canRename)
        #expect(actions.canGitPull)
        #expect(actions.canRemove)
        #expect(actions.canForceRemove)
        #expect(actions.canQuickRemove)
        #expect(actions.canShowInFinder)
        #expect(actions.canCopyPath)
    }

    @Test func contextMenuActions_singleSelected_nonRoot_allEnabled() {
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = [featureWorktree.id]

        let actions = sut.contextMenuActions(for: featureWorktree)

        #expect(actions.canOpen)
        #expect(actions.canRename)
        #expect(actions.canGitPull)
        #expect(actions.canRemove)
        #expect(actions.canForceRemove)
        #expect(actions.canShowInFinder)
        #expect(actions.canCopyPath)
    }

    @Test func contextMenuActions_singleSelected_root_removeDisabled() {
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = [rootWorktree.id]

        let actions = sut.contextMenuActions(for: rootWorktree)

        #expect(actions.canOpen)
        #expect(actions.canRename)
        #expect(actions.canGitPull)
        #expect(false == actions.canRemove)
        #expect(false == actions.canForceRemove)
        #expect(false == actions.canQuickRemove)
        #expect(actions.canShowInFinder)
        #expect(actions.canCopyPath)
    }

    @Test func contextMenuActions_singleSelected_bare_removeAndPullDisabled() {
        sut.worktrees = [rootWorktree, bareWorktree]
        sut.selectedWorktreeIDs = [bareWorktree.id]

        let actions = sut.contextMenuActions(for: bareWorktree)

        #expect(actions.canOpen)
        #expect(actions.canRename)
        #expect(false == actions.canGitPull)
        #expect(false == actions.canRemove)
        #expect(false == actions.canForceRemove)
        #expect(actions.canShowInFinder)
        #expect(actions.canCopyPath)
    }

    // MARK: Multi-select behavior (2+ selected AND right-clicked item is in selection)

    @Test func contextMenuActions_multiSelected_noRoot_onlyRemoveEnabled() {
        sut.worktrees = [rootWorktree, featureWorktree, fixWorktree]
        sut.selectedWorktreeIDs = [featureWorktree.id, fixWorktree.id]

        let actions = sut.contextMenuActions(for: featureWorktree)

        #expect(false == actions.canOpen)
        #expect(false == actions.canRename)
        #expect(false == actions.canGitPull)
        #expect(actions.canRemove)
        #expect(actions.canForceRemove)
        #expect(false == actions.canShowInFinder)
        #expect(false == actions.canCopyPath)
    }

    @Test func contextMenuActions_multiSelected_withRootIncluded_removeDisabled() {
        // Root is in selection → canRemove = false regardless of other removable items
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = [rootWorktree.id, featureWorktree.id]

        let actions = sut.contextMenuActions(for: featureWorktree)

        #expect(false == actions.canOpen)
        #expect(false == actions.canRename)
        #expect(false == actions.canGitPull)
        #expect(false == actions.canRemove)
        #expect(false == actions.canForceRemove)
        #expect(false == actions.canShowInFinder)
        #expect(false == actions.canCopyPath)
    }

    @Test func contextMenuActions_multiSelected_allNonRemovable_removeDisabled() {
        // Root + bare: neither can be removed
        sut.worktrees = [rootWorktree, bareWorktree]
        sut.selectedWorktreeIDs = [rootWorktree.id, bareWorktree.id]

        let actions = sut.contextMenuActions(for: bareWorktree)

        #expect(false == actions.canOpen)
        #expect(false == actions.canRename)
        #expect(false == actions.canGitPull)
        #expect(false == actions.canRemove)
        #expect(false == actions.canForceRemove)
        #expect(false == actions.canShowInFinder)
        #expect(false == actions.canCopyPath)
    }

    @Test func contextMenuActions_multiSelected_rightClickedNotInSelection_singleBehavior() {
        // feature + fix are selected, but we right-click on root (not in selection)
        // → treated as single-item → root rules apply
        sut.worktrees = [rootWorktree, featureWorktree, fixWorktree]
        sut.selectedWorktreeIDs = [featureWorktree.id, fixWorktree.id]

        let actions = sut.contextMenuActions(for: rootWorktree)

        #expect(actions.canOpen)
        #expect(actions.canRename)
        #expect(actions.canGitPull)
        #expect(false == actions.canRemove)       // root cannot be removed
        #expect(false == actions.canForceRemove)
        #expect(actions.canShowInFinder)
        #expect(actions.canCopyPath)
    }

    // MARK: Locked worktree — quick remove must be blocked

    @Test func contextMenuActions_lockedWorktree_canQuickRemoveIsFalse() {
        let lockedWorktree = Worktree(
            path: "/tmp/worktrees/locked-wt",
            folderName: "locked-wt",
            branch: "feature/locked",
            isLocked: true
        )
        sut.worktrees = [rootWorktree, lockedWorktree]
        sut.selectedWorktreeIDs = []

        let actions = sut.contextMenuActions(for: lockedWorktree)

        #expect(false == actions.canQuickRemove, "Locked worktree must not be quick-removable")
        // canRemove and canForceRemove should also be false for locked worktrees
        #expect(false == actions.canRemove, "Locked worktree must not be removable")
        #expect(false == actions.canForceRemove, "Locked worktree must not be force-removable")
        // Other actions should still work
        #expect(actions.canOpen)
        #expect(actions.canRename)
        #expect(actions.canGitPull)
        #expect(actions.canShowInFinder)
        #expect(actions.canCopyPath)
    }

    @Test func contextMenuActions_multiSelected_withLockedWorktree_removeDisabled() {
        let lockedWorktree = Worktree(
            path: "/tmp/worktrees/locked-wt",
            folderName: "locked-wt",
            branch: "feature/locked",
            isLocked: true
        )
        sut.worktrees = [rootWorktree, featureWorktree, lockedWorktree]
        sut.selectedWorktreeIDs = [featureWorktree.id, lockedWorktree.id]

        let actions = sut.contextMenuActions(for: featureWorktree)

        // Selection contains a locked worktree → all remove actions disabled
        #expect(false == actions.canRemove, "Multi-select with locked worktree must disable remove")
        #expect(false == actions.canForceRemove, "Multi-select with locked worktree must disable force remove")
        #expect(false == actions.canQuickRemove, "Multi-select with locked worktree must disable quick remove")
    }

    // MARK: nil-repository coverage (exercises the `?? false` fallback autoclosures)

    /// Multi-select with NO repository set. `repository.map { … }` returns nil, so the
    /// `?? false` fallback autoclosure in the `allRemovable` predicate (L24) executes.
    @Test func contextMenuActions_multiSelected_noRepository_isRootDefaultsFalse() {
        sut.repository = nil
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = [rootWorktree.id, featureWorktree.id]

        let actions = sut.contextMenuActions(for: rootWorktree)

        // With no repository, isRoot resolves to false → both worktrees look removable.
        #expect(actions.canRemove)
        #expect(actions.canForceRemove)
        #expect(actions.canQuickRemove)
        // Multi-select disables non-remove actions regardless.
        #expect(false == actions.canOpen)
        #expect(false == actions.canShowInFinder)
    }

    /// Single-item path with NO repository set. `repository.map { … }` returns nil, so the
    /// `?? false` fallback autoclosure for the single-item `isRoot` check (L44) executes.
    @Test func contextMenuActions_singleSelected_noRepository_isRootDefaultsFalse() {
        sut.repository = nil
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = []

        let actions = sut.contextMenuActions(for: rootWorktree)

        // isRoot defaults to false (no repository) → a non-bare, non-locked worktree is removable.
        #expect(actions.canRemove)
        #expect(actions.canForceRemove)
        #expect(actions.canQuickRemove)
        #expect(actions.canOpen)
        #expect(actions.canShowInFinder)
        #expect(actions.canCopyPath)
    }
}
