import XCTest

@testable import OhMyWorktree

final class WorktreeTests: XCTestCase {

    // MARK: - displayName with customName

    func testDisplayName_returnsCustomName_whenSet() {
        var worktree = Worktree(
            path: "/repo/worktrees/bright-ocean",
            folderName: "bright-ocean",
            branch: "feature/login",
            commitHash: "abc1234"
        )
        worktree.customName = "My Feature"

        XCTAssertEqual(worktree.displayName, "My Feature")
    }

    // MARK: - displayName fallback

    func testDisplayName_returnsBranch_whenCustomNameIsNil() {
        let worktree = Worktree(
            path: "/repo/worktrees/bright-ocean",
            folderName: "bright-ocean",
            branch: "feature/login",
            commitHash: "abc1234"
        )

        XCTAssertNil(worktree.customName)
        XCTAssertEqual(worktree.displayName, "feature/login")
    }

    func testDisplayName_returnsBranch_whenCustomNameIsEmpty() {
        var worktree = Worktree(
            path: "/repo/worktrees/bright-ocean",
            folderName: "bright-ocean",
            branch: "feature/login",
            commitHash: "abc1234"
        )
        worktree.customName = ""

        XCTAssertEqual(worktree.displayName, "feature/login")
    }

    func testDisplayName_returnsCustomName_whenWhitespaceOnly() {
        // Note: In practice, RepositoryStore sanitizes whitespace-only to nil.
        // The model trusts its input and returns customName as-is.
        var worktree = Worktree(
            path: "/repo/worktrees/bright-ocean",
            folderName: "bright-ocean",
            branch: "feature/login",
            commitHash: "abc1234"
        )
        worktree.customName = "   "

        XCTAssertEqual(worktree.displayName, "   ")
    }

    func testDisplayName_returnsDetached_whenNoBranchAndNoCustomName() {
        let worktree = Worktree(
            path: "/repo/worktrees/bright-ocean",
            folderName: "bright-ocean",
            commitHash: "abc1234567890"
        )

        XCTAssertEqual(worktree.displayName, "Detached (abc1234)")
    }
}
