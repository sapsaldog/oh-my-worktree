import Testing

@testable import OhMyWorktree

@Suite
struct MenuBarTitleTests {

    @Test func showWorktreeNameKeyIsStable() {
        #expect(MenuBarTitle.showWorktreeNameKey == "showWorktreeNameInMenuBar")
    }

    @Test func emptyWhenToggleOffEvenWithRepoAndWorktree() {
        #expect(
            MenuBarTitle.text(showWorktreeName: false, repoName: "repo", worktreeName: "feature/x") == ""
        )
    }

    @Test func emptyWhenToggleOffAndNothingSelected() {
        #expect(
            MenuBarTitle.text(showWorktreeName: false, repoName: nil, worktreeName: nil) == ""
        )
    }

    @Test func fallbackTitleWhenToggleOnAndNoRepo() {
        #expect(
            MenuBarTitle.text(showWorktreeName: true, repoName: nil, worktreeName: nil) == " Oh My Worktree"
        )
    }

    @Test func repoOnlyWhenToggleOnAndNoWorktree() {
        #expect(
            MenuBarTitle.text(showWorktreeName: true, repoName: "repo", worktreeName: nil) == " repo"
        )
    }

    @Test func repoAndWorktreeWhenToggleOnAndBothPresent() {
        #expect(
            MenuBarTitle.text(showWorktreeName: true, repoName: "repo", worktreeName: "feature/x")
                == " repo/feature/x"
        )
    }
}
