import Foundation
import Testing

@testable import OhMyWorktree

// MARK: - Mock Git Executor for ViewModel Tests

final class MockWorktreeExecutor: GitCommandExecuting, @unchecked Sendable {
    var worktreeListOutput: String = ""
    var lastCommitTimestamp: String = ""

    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        if arguments == ["worktree", "list", "--porcelain"] {
            return CommandResult(stdout: worktreeListOutput, stderr: "", exitCode: 0)
        }
        if arguments.first == "log" {
            return CommandResult(stdout: lastCommitTimestamp, stderr: "", exitCode: 0)
        }
        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }

    func stubWorktrees(_ porcelainOutput: String) {
        worktreeListOutput = porcelainOutput
    }
}

// MARK: - Tests

@Suite(.serialized)
@MainActor
struct WorktreeListViewModelTests {

    let mockExecutor: MockWorktreeExecutor
    let sut: WorktreeListViewModel
    let testRepo = Repository(
        name: "test-repo",
        path: "/tmp/test-repo"
    )

    init() async throws {
        mockExecutor = MockWorktreeExecutor()
        sut = WorktreeListViewModel(
            worktreeManager: WorktreeManager(executor: mockExecutor),
            store: .shared,
            pullRequestService: MockNoPRService()
        )
        sut.repository = testRepo
    }

    // MARK: - updateSelectedWorktree (via loadWorktrees)

    @Test func loadWorktrees_selectedWorktreeUpdated_whenStillPresent() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        await sut.loadWorktrees()
        sut.selectedWorktree = sut.worktrees.first(where: { $0.folderName == "feature-a" })

        // Reload — selected should still be there, updated with fresh data
        await sut.loadWorktrees()

        #expect(sut.selectedWorktree != nil)
        #expect(sut.selectedWorktree?.folderName == "feature-a")
    }

    @Test func loadWorktrees_selectedWorktreeCleared_whenRemoved() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        await sut.loadWorktrees()
        sut.selectedWorktree = sut.worktrees.first(where: { $0.folderName == "feature-a" })
        #expect(sut.selectedWorktree != nil)

        // Remove feature-a from the list
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        """)

        await sut.loadWorktrees()

        #expect(sut.selectedWorktree == nil)
    }

    // MARK: - loadWorktrees basic behavior

    @Test func loadWorktrees_populatesWorktrees() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-x
        HEAD abc2222
        branch refs/heads/feature/x

        """)

        await sut.loadWorktrees()

        #expect(sut.worktrees.count == 2)
        #expect(!sut.isLoading)
        #expect(sut.errorMessage == nil)
    }

    @Test func loadWorktrees_noRepository_clearsWorktrees() async {
        sut.repository = nil
        mockExecutor.stubWorktrees("worktree /tmp/test-repo\nHEAD abc\nbranch refs/heads/main\n")

        await sut.loadWorktrees()

        #expect(sut.worktrees.isEmpty)
    }

    @Test func loadWorktrees_debounce_skipsIfRecentlyLoaded() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        """)

        await sut.loadWorktrees()
        #expect(sut.worktrees.count == 1)

        // Change the stub — debounced call should not re-fetch
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/new-wt
        HEAD abc2222
        branch refs/heads/feature/new

        """)

        await sut.loadWorktrees(debounce: true)

        // Still 1 — debounce skipped the reload
        #expect(sut.worktrees.count == 1)
    }

    // MARK: - renameWorktree

    @Test func renameWorktree_updatesLocalState() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        await sut.loadWorktrees()
        let worktree = sut.worktrees.first(where: { $0.folderName == "feature-a" })!
        sut.selectedWorktree = worktree

        await sut.renameWorktree(worktree, newName: "My Feature")

        #expect(sut.worktrees.first(where: { $0.folderName == "feature-a" })?.customName == "My Feature")
        #expect(sut.selectedWorktree?.customName == "My Feature")
    }

    @Test func renameWorktree_whitespaceOnlyName_clearsCustomName() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        await sut.loadWorktrees()
        let worktree = sut.worktrees.first(where: { $0.folderName == "feature-a" })!

        await sut.renameWorktree(worktree, newName: "   ")

        #expect(sut.worktrees.first(where: { $0.folderName == "feature-a" })?.customName == nil)
    }

    // MARK: - Shared Fixtures

    /// Root worktree — same path as testRepo, cannot be removed
    var rootWorktree: Worktree {
        Worktree(path: testRepo.path, folderName: "test-repo", branch: "main")
    }

    /// Normal non-root worktree
    var featureWorktree: Worktree {
        Worktree(path: "/tmp/worktrees/feature-a", folderName: "feature-a", branch: "feature/a")
    }
}

// MARK: - addWorktreeFromPR

extension WorktreeListViewModelTests {

    @Test func addWorktreeFromPR_branchNotCheckedOut_enquesWithSameLocalBranch() {
        sut.worktrees = [rootWorktree]

        let pr = PullRequestInfo(
            number: 1,
            url: URL(string: "https://github.com/user/repo/pull/1")!,
            branch: "feature/new",
            state: .open
        )

        let error = sut.addWorktreeFromPR(pr)

        #expect(error == nil)
        #expect(sut.jobQueue.jobs.count == 1)
        guard case .addWorktreeFromPR(let remote, let local, _) = sut.jobQueue.jobs[0].kind else {
            Issue.record("Expected addWorktreeFromPR job kind")
            return
        }
        #expect(remote == "feature/new")
        #expect(local == "feature/new")
    }

    @Test func addWorktreeFromPR_branchAlreadyCheckedOut_enquesWithVersionedLocalBranch() {
        sut.worktrees = [
            rootWorktree,
            Worktree(path: "/tmp/worktrees/feature-a", folderName: "feature-a", branch: "feature/a")
        ]

        let pr = PullRequestInfo(
            number: 2,
            url: URL(string: "https://github.com/user/repo/pull/2")!,
            branch: "feature/a",
            state: .open
        )

        let error = sut.addWorktreeFromPR(pr)

        #expect(error == nil)
        #expect(sut.jobQueue.jobs.count == 1)
        guard case .addWorktreeFromPR(let remote, let local, _) = sut.jobQueue.jobs[0].kind else {
            Issue.record("Expected addWorktreeFromPR job kind")
            return
        }
        #expect(remote == "feature/a")
        #expect(local == "feature/a-v2")
        // Folder name is now a random name, not branch-derived.
        #expect(!sut.jobQueue.jobs[0].folderName.isEmpty)
    }
}

// MARK: - gitPull

extension WorktreeListViewModelTests {

    @Test func gitPull_enqueuesJobForWorktree() {
        sut.worktrees = [rootWorktree, featureWorktree]

        sut.gitPull(featureWorktree)

        #expect(sut.jobQueue.jobs.count == 1)
        #expect(sut.jobQueue.jobs[0].kind == .pull)
        #expect(sut.jobQueue.jobs[0].worktreeID == featureWorktree.id)
    }

    @Test func gitPull_noRepository_doesNotEnqueue() {
        sut.repository = nil
        let worktree = featureWorktree

        sut.gitPull(worktree)

        #expect(sut.jobQueue.jobs.isEmpty)
    }

    @Test func gitPull_busyWorktree_doesNotDuplicate() {
        sut.worktrees = [rootWorktree, featureWorktree]

        sut.gitPull(featureWorktree)
        sut.gitPull(featureWorktree) // second pull for same worktree

        // Should be 1 — second call is guarded by busyWorktreeIDs
        #expect(sut.jobQueue.jobs.count == 1)
    }
}

// MARK: - removeWorktree

extension WorktreeListViewModelTests {

    @Test func removeWorktree_enqueuesJobForWorktree() {
        sut.worktrees = [rootWorktree, featureWorktree]

        sut.removeWorktree(featureWorktree)

        #expect(sut.jobQueue.jobs.count == 1)
        #expect(sut.jobQueue.jobs[0].kind == .removeWorktree(force: false))
        #expect(sut.jobQueue.jobs[0].worktreeID == featureWorktree.id)
    }

    @Test func removeWorktree_force_enqueuesForceJob() {
        sut.worktrees = [rootWorktree, featureWorktree]

        sut.removeWorktree(featureWorktree, force: true)

        #expect(sut.jobQueue.jobs.count == 1)
        #expect(sut.jobQueue.jobs[0].kind == .removeWorktree(force: true))
    }

    @Test func removeWorktree_noRepository_doesNotEnqueue() {
        sut.repository = nil

        sut.removeWorktree(featureWorktree)

        #expect(sut.jobQueue.jobs.isEmpty)
    }

    // MARK: - PendingDelete

    @Test func pendingDelete_initiallyNil() {
        #expect(sut.pendingDelete == nil)
    }

    @Test func pendingDelete_canBeSetAndCleared() {
        sut.pendingDelete = .remove
        #expect(sut.pendingDelete == .remove)

        sut.pendingDelete = .forceRemove
        #expect(sut.pendingDelete == .forceRemove)

        sut.pendingDelete = .quickRemove
        #expect(sut.pendingDelete == .quickRemove)

        sut.pendingDelete = nil
        #expect(sut.pendingDelete == nil)
    }

}

// MockNoPRService is defined in MockGitExecutor.swift
