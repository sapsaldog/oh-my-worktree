import XCTest

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

    func test_contextMenuActions_nothingSelected_nonRoot_allEnabled() {
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = []

        let actions = sut.contextMenuActions(for: featureWorktree)

        XCTAssertTrue(actions.canOpen)
        XCTAssertTrue(actions.canRename)
        XCTAssertTrue(actions.canGitPull)
        XCTAssertTrue(actions.canRemove)
        XCTAssertTrue(actions.canForceRemove)
        XCTAssertTrue(actions.canQuickRemove)
        XCTAssertTrue(actions.canShowInFinder)
        XCTAssertTrue(actions.canCopyPath)
    }

    func test_contextMenuActions_singleSelected_nonRoot_allEnabled() {
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = [featureWorktree.id]

        let actions = sut.contextMenuActions(for: featureWorktree)

        XCTAssertTrue(actions.canOpen)
        XCTAssertTrue(actions.canRename)
        XCTAssertTrue(actions.canGitPull)
        XCTAssertTrue(actions.canRemove)
        XCTAssertTrue(actions.canForceRemove)
        XCTAssertTrue(actions.canShowInFinder)
        XCTAssertTrue(actions.canCopyPath)
    }

    func test_contextMenuActions_singleSelected_root_removeDisabled() {
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = [rootWorktree.id]

        let actions = sut.contextMenuActions(for: rootWorktree)

        XCTAssertTrue(actions.canOpen)
        XCTAssertTrue(actions.canRename)
        XCTAssertTrue(actions.canGitPull)
        XCTAssertFalse(actions.canRemove)
        XCTAssertFalse(actions.canForceRemove)
        XCTAssertFalse(actions.canQuickRemove)
        XCTAssertTrue(actions.canShowInFinder)
        XCTAssertTrue(actions.canCopyPath)
    }

    func test_contextMenuActions_singleSelected_bare_removeAndPullDisabled() {
        sut.worktrees = [rootWorktree, bareWorktree]
        sut.selectedWorktreeIDs = [bareWorktree.id]

        let actions = sut.contextMenuActions(for: bareWorktree)

        XCTAssertTrue(actions.canOpen)
        XCTAssertTrue(actions.canRename)
        XCTAssertFalse(actions.canGitPull)
        XCTAssertFalse(actions.canRemove)
        XCTAssertFalse(actions.canForceRemove)
        XCTAssertTrue(actions.canShowInFinder)
        XCTAssertTrue(actions.canCopyPath)
    }

    // MARK: Multi-select behavior (2+ selected AND right-clicked item is in selection)

    func test_contextMenuActions_multiSelected_noRoot_onlyRemoveEnabled() {
        sut.worktrees = [rootWorktree, featureWorktree, fixWorktree]
        sut.selectedWorktreeIDs = [featureWorktree.id, fixWorktree.id]

        let actions = sut.contextMenuActions(for: featureWorktree)

        XCTAssertFalse(actions.canOpen)
        XCTAssertFalse(actions.canRename)
        XCTAssertFalse(actions.canGitPull)
        XCTAssertTrue(actions.canRemove)
        XCTAssertTrue(actions.canForceRemove)
        XCTAssertFalse(actions.canShowInFinder)
        XCTAssertFalse(actions.canCopyPath)
    }

    func test_contextMenuActions_multiSelected_withRootIncluded_removeDisabled() {
        // Root is in selection → canRemove = false regardless of other removable items
        sut.worktrees = [rootWorktree, featureWorktree]
        sut.selectedWorktreeIDs = [rootWorktree.id, featureWorktree.id]

        let actions = sut.contextMenuActions(for: featureWorktree)

        XCTAssertFalse(actions.canOpen)
        XCTAssertFalse(actions.canRename)
        XCTAssertFalse(actions.canGitPull)
        XCTAssertFalse(actions.canRemove)
        XCTAssertFalse(actions.canForceRemove)
        XCTAssertFalse(actions.canShowInFinder)
        XCTAssertFalse(actions.canCopyPath)
    }

    func test_contextMenuActions_multiSelected_allNonRemovable_removeDisabled() {
        // Root + bare: neither can be removed
        sut.worktrees = [rootWorktree, bareWorktree]
        sut.selectedWorktreeIDs = [rootWorktree.id, bareWorktree.id]

        let actions = sut.contextMenuActions(for: bareWorktree)

        XCTAssertFalse(actions.canOpen)
        XCTAssertFalse(actions.canRename)
        XCTAssertFalse(actions.canGitPull)
        XCTAssertFalse(actions.canRemove)
        XCTAssertFalse(actions.canForceRemove)
        XCTAssertFalse(actions.canShowInFinder)
        XCTAssertFalse(actions.canCopyPath)
    }

    func test_contextMenuActions_multiSelected_rightClickedNotInSelection_singleBehavior() {
        // feature + fix are selected, but we right-click on root (not in selection)
        // → treated as single-item → root rules apply
        sut.worktrees = [rootWorktree, featureWorktree, fixWorktree]
        sut.selectedWorktreeIDs = [featureWorktree.id, fixWorktree.id]

        let actions = sut.contextMenuActions(for: rootWorktree)

        XCTAssertTrue(actions.canOpen)
        XCTAssertTrue(actions.canRename)
        XCTAssertTrue(actions.canGitPull)
        XCTAssertFalse(actions.canRemove)       // root cannot be removed
        XCTAssertFalse(actions.canForceRemove)
        XCTAssertTrue(actions.canShowInFinder)
        XCTAssertTrue(actions.canCopyPath)
    }

    // MARK: Locked worktree — quick remove must be blocked

    func testContextMenuActions_lockedWorktree_canQuickRemoveIsFalse() {
        let lockedWorktree = Worktree(
            path: "/tmp/worktrees/locked-wt",
            folderName: "locked-wt",
            branch: "feature/locked",
            isLocked: true
        )
        sut.worktrees = [rootWorktree, lockedWorktree]
        sut.selectedWorktreeIDs = []

        let actions = sut.contextMenuActions(for: lockedWorktree)

        XCTAssertFalse(actions.canQuickRemove, "Locked worktree must not be quick-removable")
        // canRemove and canForceRemove should also be false for locked worktrees
        XCTAssertFalse(actions.canRemove, "Locked worktree must not be removable")
        XCTAssertFalse(actions.canForceRemove, "Locked worktree must not be force-removable")
        // Other actions should still work
        XCTAssertTrue(actions.canOpen)
        XCTAssertTrue(actions.canRename)
        XCTAssertTrue(actions.canGitPull)
        XCTAssertTrue(actions.canShowInFinder)
        XCTAssertTrue(actions.canCopyPath)
    }

    func testContextMenuActions_multiSelected_withLockedWorktree_removeDisabled() {
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
        XCTAssertFalse(actions.canRemove, "Multi-select with locked worktree must disable remove")
        XCTAssertFalse(actions.canForceRemove, "Multi-select with locked worktree must disable force remove")
        XCTAssertFalse(actions.canQuickRemove, "Multi-select with locked worktree must disable quick remove")
    }
}
