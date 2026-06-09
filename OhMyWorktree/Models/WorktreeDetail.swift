import Foundation

/// Commits a worktree is ahead/behind its upstream tracking branch.
struct AheadBehind: Equatable, Sendable {
    let ahead: Int
    let behind: Int
}

/// Aggregate diff statistics for a worktree vs. its base branch.
struct DiffStat: Equatable, Sendable {
    let added: Int
    let removed: Int
    let files: Int

    var isEmpty: Bool { files == 0 }
}

/// A single commit in the recent-commits list.
struct Commit: Identifiable, Equatable, Sendable {
    let hash: String
    let message: String
    let author: String
    let date: Date?

    var id: String { hash }
}

/// Everything the detail pane shows beyond the worktree's own fields.
struct WorktreeDetail: Equatable, Sendable {
    var aheadBehind: AheadBehind?
    var diff: DiffStat
    var commits: [Commit]
    /// Files copied into the worktree per `.worktreeinclude` (or `.env*`),
    /// each classified against main (the repository copy) for diff display.
    var copiedFiles: [CopiedFile] = []

    static let empty = WorktreeDetail(
        aheadBehind: nil,
        diff: DiffStat(added: 0, removed: 0, files: 0),
        commits: [],
        copiedFiles: []
    )
}
