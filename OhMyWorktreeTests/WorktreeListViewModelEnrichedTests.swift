import XCTest

@testable import OhMyWorktree

// MARK: - enriched() concurrent commit date tests
// Tests for the TaskGroup-based parallel commit date fetching in WorktreeListViewModel.enriched()

@MainActor
final class WorktreeListViewModelEnrichedTests: XCTestCase {

    var mockExecutor: MockWorktreeExecutor!
    var sut: WorktreeListViewModel!
    let testRepo = Repository(
        name: "test-repo",
        path: "/tmp/test-repo"
    )

    override func setUp() async throws {
        try await super.setUp()
        mockExecutor = MockWorktreeExecutor()
        sut = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: mockExecutor),
            store: .shared,
            pullRequestService: MockNoPRService()
        )
        sut.repository = testRepo
    }

    // MARK: - Helpers

    private var commitTimestamp1000: String { "1000" }
    private var commitTimestamp2000: String { "2000" }
    private var commitDate1000: Date { Date(timeIntervalSince1970: 1000) }
    private var commitDate2000: Date { Date(timeIntervalSince1970: 2000) }
    private var metadataDate1500: Date { Date(timeIntervalSince1970: 1500) }
    private var metadataDate3000: Date { Date(timeIntervalSince1970: 3000) }

    // MARK: - Tests

    /// When both metadata and commit dates exist, enriched() should pick the max.
    func testEnriched_mergesCommitAndMetadataDates_takingMax() async {
        mockExecutor.commitTimestampsByPath["/tmp/worktrees/feature-a"] = commitTimestamp2000
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        let meta = WorktreeMetadata(
            folderName: "feature-a",
            lastActivityAt: metadataDate1500
        )
        await sut.store.addWorktreeMetadata(meta, repositoryID: testRepo.id)

        await sut.loadWorktrees()

        let featureWt = sut.worktrees.first(where: { $0.folderName == "feature-a" })
        XCTAssertNotNil(featureWt)
        XCTAssertEqual(featureWt?.lastActivityAt, commitDate2000,
                       "Should pick the later date (commit=2000 > metadata=1500)")
    }

    /// When both metadata and commit dates exist, enriched() should pick the max (metadata wins).
    func testEnriched_mergesCommitAndMetadataDates_metadataWins() async {
        mockExecutor.commitTimestampsByPath["/tmp/worktrees/feature-a"] = commitTimestamp1000
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        let meta = WorktreeMetadata(
            folderName: "feature-a",
            lastActivityAt: metadataDate3000
        )
        await sut.store.addWorktreeMetadata(meta, repositoryID: testRepo.id)

        await sut.loadWorktrees()

        let featureWt = sut.worktrees.first(where: { $0.folderName == "feature-a" })
        XCTAssertNotNil(featureWt)
        XCTAssertEqual(featureWt?.lastActivityAt, metadataDate3000,
                       "Should pick the later date (metadata=3000 > commit=1000)")
    }

    /// When commit date is nil (e.g. empty repo), enriched() should use metadata date alone.
    func testEnriched_nilCommitDate_usesMetadataDate() async {
        mockExecutor.commitTimestampsByPath["/tmp/worktrees/feature-a"] = ""
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        let meta = WorktreeMetadata(
            folderName: "feature-a",
            lastActivityAt: metadataDate1500
        )
        await sut.store.addWorktreeMetadata(meta, repositoryID: testRepo.id)

        await sut.loadWorktrees()

        let featureWt = sut.worktrees.first(where: { $0.folderName == "feature-a" })
        XCTAssertNotNil(featureWt)
        XCTAssertEqual(featureWt?.lastActivityAt, metadataDate1500,
                       "Should use metadata date when commit date is nil")
    }

    /// When metadata has no lastActivityAt (no matching metadata), enriched() should use commit date.
    func testEnriched_nilMetadataDate_usesCommitDate() async {
        mockExecutor.commitTimestampsByPath["/tmp/worktrees/feature-a"] = commitTimestamp2000
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        // Do NOT add metadata for "feature-a" -> meta will be nil

        await sut.loadWorktrees()

        let featureWt = sut.worktrees.first(where: { $0.folderName == "feature-a" })
        XCTAssertNotNil(featureWt)
        XCTAssertEqual(featureWt?.lastActivityAt, commitDate2000,
                       "Should use commit date when metadata is nil")
    }

    /// When the parent Task is cancelled, enriched() should return early without crashing.
    func testEnriched_cancellation_doesNotCrash() async {
        mockExecutor.commitTimestampsByPath["/tmp/worktrees/feature-a"] = commitTimestamp2000
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        let task = Task { @MainActor in
            await sut.loadWorktrees()
        }

        // Cancel immediately -- enriched() should handle this gracefully
        task.cancel()
        await task.value

        // The test passes if we reach here without crashing.
        // Worktrees may be empty (cancellation) or populated (if finished before cancel).
        XCTAssertTrue(true, "enriched() handled cancellation without crashing")
    }

    /// Multiple worktrees should all get their commit dates (verifies concurrency correctness).
    func testEnriched_multipleWorktrees_allGetCommitDates() async {
        mockExecutor.commitTimestampsByPath["/tmp/test-repo"] = commitTimestamp1000
        mockExecutor.commitTimestampsByPath["/tmp/worktrees/feature-a"] = commitTimestamp2000
        mockExecutor.commitTimestampsByPath["/tmp/worktrees/fix-b"] = "3000"
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        worktree /tmp/worktrees/fix-b
        HEAD abc3333
        branch refs/heads/fix/b

        """)

        await sut.loadWorktrees()

        XCTAssertEqual(sut.worktrees.count, 3)
        for wt in sut.worktrees {
            XCTAssertNotNil(wt.lastActivityAt,
                            "Worktree '\(wt.folderName)' should have a lastActivityAt date")
        }
    }
}
