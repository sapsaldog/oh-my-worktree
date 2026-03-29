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

/// All stored properties are `let` — `@unchecked Sendable` is safe because
/// no mutation occurs after initialization.
private final class ConcurrencyTrackingExecutor: GitCommandExecuting, @unchecked Sendable {
    let worktreeListOutput: String
    let commitTimestampsByPath: [String: String]
    let defaultTimestamp: String
    let logCallDelay: Duration
    let tracker = ConcurrencyTracker()

    init(
        worktreeListOutput: String = "",
        commitTimestampsByPath: [String: String] = [:],
        defaultTimestamp: String = "1700000000",
        logCallDelay: Duration = .milliseconds(50)
    ) {
        self.worktreeListOutput = worktreeListOutput
        self.commitTimestampsByPath = commitTimestampsByPath
        self.defaultTimestamp = defaultTimestamp
        self.logCallDelay = logCallDelay
    }

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
            // swiftlint:disable:next no_arbitrary_delay
            try? await Task.sleep(for: logCallDelay)
            await tracker.exit()
            let ts = commitTimestampsByPath[workingDirectory ?? ""] ?? defaultTimestamp
            return CommandResult(stdout: ts, stderr: "", exitCode: 0)
        }
        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

// MARK: - Tests

@Suite("WorktreeListViewModel enrichment",
       .bug("https://github.com/sapsaldog/oh-my-worktree/issues/12",
            "Parallel commit-date enrichment"))
@MainActor
struct WorktreeListViewModelEnrichmentTests {

    private let testRepo = Repository(name: "test-repo", path: "/tmp/test-repo")

    private let threeWorktreesPorcelain = """
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

    // MARK: - Concurrent execution

    @Test("lastCommitDate calls run concurrently for multiple worktrees")
    func enrichment_fetchesCommitDatesConcurrently() async {
        let executor = ConcurrencyTrackingExecutor(
            worktreeListOutput: threeWorktreesPorcelain
        )

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
    func enrichment_mapsCorrectDatesToWorktrees() async throws {
        let executor = ConcurrencyTrackingExecutor(
            worktreeListOutput: threeWorktreesPorcelain,
            commitTimestampsByPath: [
                "/tmp/test-repo": "1700000100",
                "/tmp/worktrees/wt-a": "1700000200",
                "/tmp/worktrees/wt-b": "1700000300"
            ],
            logCallDelay: .zero
        )

        let vm = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: executor),
            store: .shared,
            pullRequestService: MockNoPRService()
        )
        vm.repository = testRepo

        await vm.loadWorktrees()

        try #require(vm.worktrees.count == 3, "enrichment requires exactly 3 worktrees")

        let worktreeByName = Dictionary(
            uniqueKeysWithValues: vm.worktrees.map { ($0.folderName, $0) }
        )

        let main = try #require(worktreeByName["test-repo"], "missing test-repo worktree")
        let wtA = try #require(worktreeByName["wt-a"], "missing wt-a worktree")
        let wtB = try #require(worktreeByName["wt-b"], "missing wt-b worktree")

        #expect(main.lastActivityAt == Date(timeIntervalSince1970: 1_700_000_100))
        #expect(wtA.lastActivityAt == Date(timeIntervalSince1970: 1_700_000_200))
        #expect(wtB.lastActivityAt == Date(timeIntervalSince1970: 1_700_000_300))
    }
}
