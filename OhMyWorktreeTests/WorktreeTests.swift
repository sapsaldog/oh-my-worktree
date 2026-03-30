import Testing

@testable import OhMyWorktree

@Suite struct WorktreeTests {

    // MARK: - displayName with customName

    @Test func displayName_returnsCustomName_whenSet() {
        var worktree = Worktree(
            path: "/repo/worktrees/bright-ocean",
            folderName: "bright-ocean",
            branch: "feature/login",
            commitHash: "abc1234"
        )
        worktree.customName = "My Feature"

        #expect(worktree.displayName == "My Feature")
    }

    // MARK: - displayName fallback

    @Test func displayName_returnsBranch_whenCustomNameIsNil() {
        let worktree = Worktree(
            path: "/repo/worktrees/bright-ocean",
            folderName: "bright-ocean",
            branch: "feature/login",
            commitHash: "abc1234"
        )

        #expect(worktree.customName == nil)
        #expect(worktree.displayName == "feature/login")
    }

    @Test func displayName_returnsBranch_whenCustomNameIsEmpty() {
        var worktree = Worktree(
            path: "/repo/worktrees/bright-ocean",
            folderName: "bright-ocean",
            branch: "feature/login",
            commitHash: "abc1234"
        )
        worktree.customName = ""

        #expect(worktree.displayName == "feature/login")
    }

    @Test func displayName_returnsCustomName_whenWhitespaceOnly() {
        var worktree = Worktree(
            path: "/repo/worktrees/bright-ocean",
            folderName: "bright-ocean",
            branch: "feature/login",
            commitHash: "abc1234"
        )
        worktree.customName = "   "

        #expect(worktree.displayName == "   ")
    }

    @Test func displayName_returnsDetached_whenNoBranchAndNoCustomName() {
        let worktree = Worktree(
            path: "/repo/worktrees/bright-ocean",
            folderName: "bright-ocean",
            commitHash: "abc1234567890"
        )

        #expect(worktree.displayName == "Detached (abc1234)")
    }
}
