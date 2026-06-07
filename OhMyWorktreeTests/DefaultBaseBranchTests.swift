import Testing

@testable import OhMyWorktree

/// `WorktreeListViewModel.defaultBaseBranch(from:)` picks which branch the
/// New Worktree sheet pre-selects: prefer `main`, then `master`, else the first
/// available branch (or `main` when the list is empty).
struct DefaultBaseBranchTests {

    @Test func prefersMainWhenPresent() {
        #expect(WorktreeListViewModel.defaultBaseBranch(from: ["agile-eagle", "main", "zeta"]) == "main")
    }

    @Test func prefersSecondChoiceWhenMainAbsent() {
        #expect(WorktreeListViewModel.defaultBaseBranch(from: ["agile-eagle", "master", "zeta"]) == "master")
    }

    @Test func mainWinsWhenBothPresent() {
        #expect(WorktreeListViewModel.defaultBaseBranch(from: ["master", "main"]) == "main")
    }

    @Test func fallsBackToFirstWhenNeitherPresent() {
        #expect(WorktreeListViewModel.defaultBaseBranch(from: ["agile-eagle", "zeta"]) == "agile-eagle")
    }

    @Test func fallsBackToMainWhenEmpty() {
        #expect(WorktreeListViewModel.defaultBaseBranch(from: []) == "main")
    }
}

/// `WorktreeListViewModel.filterBranches(_:matching:)` powers the New Worktree
/// sheet's "More…" branch search: case-insensitive substring match, trimmed,
/// returning every branch when the query is blank.
struct BranchFilterTests {
    private let branches = ["main", "develop", "feature/login", "feature/signup", "release/2.0"]

    @Test func emptyQueryReturnsAll() {
        #expect(WorktreeListViewModel.filterBranches(branches, matching: "") == branches)
    }

    @Test func whitespaceQueryReturnsAll() {
        #expect(WorktreeListViewModel.filterBranches(branches, matching: "   ") == branches)
    }

    @Test func matchesCaseInsensitiveSubstring() {
        #expect(WorktreeListViewModel.filterBranches(branches, matching: "FEATURE") == ["feature/login", "feature/signup"])
    }

    @Test func matchesAnywhereInName() {
        #expect(WorktreeListViewModel.filterBranches(branches, matching: "login") == ["feature/login"])
    }

    @Test func noMatchReturnsEmpty() {
        #expect(WorktreeListViewModel.filterBranches(branches, matching: "zzz").isEmpty)
    }
}
