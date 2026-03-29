import Foundation
import Testing

@testable import OhMyWorktree

// MARK: - Concurrency-tracking executor

/// Records peak concurrent `git log` calls to verify parallel execution.
private actor ConcurrencyTracker {
    private var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        if current > peak { peak = current }
    }

    func exit() {
        current -= 1
    }
}

private final class ConcurrencyTrackingExecutor: GitCommandExecuting, @unchecked Sendable {
    var worktreeListOutput: String = ""
    /// Per-path commit timestamps; key = workingDirectory.
    var commitTimestampsByPath: [String: String] = [:]
    /// Fallback timestamp when path is not in `commitTimestampsByPath`.
    var defaultTimestamp: String = "1700000000"
    /// Artificial delay per `git log` call so concurrent tasks overlap.
    var logCallDelay: UInt64 = 50_000_000 // 50 ms

    let tracker = ConcurrencyTracker()

    func execute(
        command: String,
        arguments: [String],
        workingDirectory: String?
    ) async throws -> CommandResult {
        if arguments == ["worktree", "list", "--porcelain"] {
            return CommandResult(stdout: worktreeListOutput, stderr: "", exitCode: 0)
        }
        if arguments.first == "log" {
            await tracker.enter()
            try? await Task.sleep(nanoseconds: logCallDelay)
            await tracker.exit()
            let ts = commitTimestampsByPath[workingDirectory ?? ""] ?? defaultTimestamp
            return CommandResult(stdout: ts, stderr: "", exitCode: 0)
        }
        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

// MARK: - Tests

@Suite("WorktreeListViewModel enrichment (issue #12)")
@MainActor
struct WorktreeListViewModelEnrichmentTests {

    private let testRepo = Repository(name: "test-repo", path: "/tmp/test-repo")

    // MARK: - Concurrent execution

    @Test("lastCommitDate calls run concurrently for multiple worktrees")
    func enrichment_fetchesCommitDatesConcurrently() async {
        let executor = ConcurrencyTrackingExecutor()
        executor.worktreeListOutput = """
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/wt-a
        HEAD abc2222
        branch refs/heads/feature/a

        worktree /tmp/worktrees/wt-b
        HEAD abc3333
        branch refs/heads/feature/b

        """

        let vm = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: executor),
            store: .shared,
            pullRequestService: MockNoPRService()
        )
        vm.repository = testRepo

        await vm.loadWorktrees()

        let peak = await executor.tracker.peak
        #expect(peak > 1, "git log calls should overlap — peak was \(peak)")
    }

    // MARK: - Correct date mapping

    @Test("each worktree gets its own commit date after parallel enrichment")
    func enrichment_mapsCorrectDatesToWorktrees() async {
        let executor = ConcurrencyTrackingExecutor()
        executor.worktreeListOutput = """
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/wt-a
        HEAD abc2222
        branch refs/heads/feature/a

        worktree /tmp/worktrees/wt-b
        HEAD abc3333
        branch refs/heads/feature/b

        """
        // Each path returns a distinct timestamp
        executor.commitTimestampsByPath = [
            "/tmp/test-repo": "1700000100",       // 2023-11-14T22:48:20Z
            "/tmp/worktrees/wt-a": "1700000200",  // 2023-11-14T22:50:00Z
            "/tmp/worktrees/wt-b": "1700000300"   // 2023-11-14T22:51:40Z
        ]
        executor.logCallDelay = 0 // no delay needed for correctness test

        let vm = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: executor),
            store: .shared,
            pullRequestService: MockNoPRService()
        )
        vm.repository = testRepo

        await vm.loadWorktrees()

        let dates = Dictionary(
            uniqueKeysWithValues: vm.worktrees.map { ($0.folderName, $0.lastActivityAt) }
        )

        #expect(dates["test-repo"] == Date(timeIntervalSince1970: 1_700_000_100))
        #expect(dates["wt-a"] == Date(timeIntervalSince1970: 1_700_000_200))
        #expect(dates["wt-b"] == Date(timeIntervalSince1970: 1_700_000_300))
    }
}
