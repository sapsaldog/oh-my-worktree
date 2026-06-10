import Foundation
import Testing

@testable import OhMyWorktree

// MARK: - Mock executor (porcelain list + check-ignore echo)

/// Serves `worktree list --porcelain` from a fixture and echoes `check-ignore`
/// candidates back (treats every copied file as git-ignored); everything else
/// succeeds with empty output.
private final class RefreshGitExecutor: GitCommandExecuting, @unchecked Sendable {
    var worktreeListOutput = ""

    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        if arguments == ["worktree", "list", "--porcelain"] {
            return CommandResult(stdout: worktreeListOutput, stderr: "", exitCode: 0)
        }
        if arguments.first == "check-ignore" {
            let candidates = arguments.drop(while: { $0 != "--" }).dropFirst()
            return CommandResult(stdout: candidates.joined(separator: "\n"), stderr: "", exitCode: 0)
        }
        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

// MARK: - Detail refresh on list reload

/// Editing a copied file (e.g. `.env`) must be picked up by the refresh paths the
/// app already has (activation, ⌘R, toolbar, menu) — all of which call
/// `loadWorktrees`. The selected worktree's detail (copied-file diff statuses)
/// must therefore refresh with the list, not only on selection change.
@Suite(.serialized)
@MainActor
final class WorktreeListViewModelDetailRefreshTests {

    private let repoDir: String
    private let wtDir: String
    private let fm = FileManager.default
    private let executor = RefreshGitExecutor()
    private let sut: WorktreeListViewModel

    init() {
        let base = NSTemporaryDirectory() + "DetailRefreshTests-\(UUID().uuidString)"
        repoDir = base + "/repo"
        wtDir = base + "/wt-feature"
        try! fm.createDirectory(atPath: repoDir, withIntermediateDirectories: true)
        try! fm.createDirectory(atPath: wtDir, withIntermediateDirectories: true)
        sut = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: executor, fileManager: MockNoOpFileManager()),
            store: .shared,
            pullRequestService: MockNoPRService()
        )
        sut.repository = Repository(name: "refresh-test", path: repoDir)
        executor.worktreeListOutput = """
        worktree \(repoDir)
        HEAD abc1111
        branch refs/heads/main

        worktree \(wtDir)
        HEAD abc2222
        branch refs/heads/feature/x

        """
    }

    deinit {
        let base = (repoDir as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: base)
    }

    private func write(_ name: String, _ text: String, in dir: String) {
        fm.createFile(atPath: (dir as NSString).appendingPathComponent(name), contents: Data(text.utf8))
    }

    @Test func loadWorktreesRefreshesSelectedWorktreeDetail() async {
        write(".env", "A=1", in: repoDir)
        write(".env", "A=1", in: wtDir)
        await sut.loadWorktrees()
        guard let feature = sut.worktrees.first(where: { $0.path == wtDir }) else {
            Issue.record("feature worktree missing from \(sut.worktrees.map(\.path))")
            return
        }
        sut.selectedWorktreeIDs = [feature.id]
        await sut.loadDetail(for: feature)
        #expect(sut.selectedWorktreeDetail?.copiedFiles.map(\.status) == [.identical])

        // Edit the worktree's copy on disk, then refresh the list — the path every
        // refresh trigger takes. The diff status must follow without reselecting.
        write(".env", "A=1\nB=2", in: wtDir)
        await sut.loadWorktrees()
        #expect(sut.selectedWorktreeDetail?.copiedFiles.map(\.status) == [.modified])
    }

    @Test func loadWorktreesWithoutSelectionLeavesDetailEmpty() async {
        write(".env", "A=1", in: wtDir)
        await sut.loadWorktrees()
        #expect(sut.selectedWorktreeDetail == nil)
    }

    /// Regression: a `.worktreeinclude` file present in main but never copied into
    /// the worktree must surface as `.missing` (not vanish from the diff), and the
    /// reverse copy must perform the skipped copy and flip it to identical.
    @Test func uncopiedMainFileSurfacesAsMissingThenCopiesIntoWorktree() async {
        write(".env", "A=1\nB=2", in: repoDir)   // main only — copy never happened
        await sut.loadWorktrees()
        guard let feature = sut.worktrees.first(where: { $0.path == wtDir }) else {
            Issue.record("feature worktree missing from \(sut.worktrees.map(\.path))")
            return
        }
        sut.selectedWorktreeIDs = [feature.id]
        await sut.loadDetail(for: feature)
        #expect(sut.selectedWorktreeDetail?.copiedFiles.map(\.status) == [.missing])

        guard let missing = sut.selectedWorktreeDetail?.copiedFiles.first else {
            Issue.record("missing file absent from detail")
            return
        }
        await sut.applyCopiedFileToWorktree(missing, in: feature)
        #expect(fm.contents(atPath: (wtDir as NSString).appendingPathComponent(".env"))
            == Data("A=1\nB=2".utf8))
        #expect(sut.selectedWorktreeDetail?.copiedFiles.map(\.status) == [.identical])
    }

    @Test func debouncedLoadWorktreesStillRefreshesDetail() async {
        write(".env", "A=1", in: repoDir)
        write(".env", "A=1", in: wtDir)
        await sut.loadWorktrees()
        guard let feature = sut.worktrees.first(where: { $0.path == wtDir }) else {
            Issue.record("feature worktree missing from \(sut.worktrees.map(\.path))")
            return
        }
        sut.selectedWorktreeIDs = [feature.id]
        await sut.loadDetail(for: feature)
        #expect(sut.selectedWorktreeDetail?.copiedFiles.map(\.status) == [.identical])

        // Edit the file, then refresh via the DEBOUNCED path (app activation,
        // menu-bar open) inside the 2s window. The list reload is skipped — the
        // selected worktree's detail must still pick up the file change.
        write(".env", "A=1\nB=2", in: wtDir)
        await sut.loadWorktrees(debounce: true)
        #expect(sut.selectedWorktreeDetail?.copiedFiles.map(\.status) == [.modified])
    }
}
