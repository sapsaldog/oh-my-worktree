import Foundation
import Testing

@testable import OhMyWorktree

// MARK: - Mock

private final class MockGitExecutor: GitCommandExecuting, @unchecked Sendable {
    var stubbedResult: CommandResult = CommandResult(stdout: "", stderr: "", exitCode: 0)
    var stubbedError: Error?
    var executedCommands: [[String]] = []

    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        executedCommands.append(arguments)
        if let error = stubbedError { throw error }
        return stubbedResult
    }

    func stub(stdout: String, exitCode: Int32 = 0) {
        stubbedResult = CommandResult(stdout: stdout, stderr: "", exitCode: exitCode)
    }

    func stubError(_ error: Error) {
        stubbedError = error
    }
}

// MARK: - Mock FileManager

private final class MockFileManager: FileManaging, @unchecked Sendable {
    var trashedURLs: [URL] = []
    var shouldFailTrash = false
    var existingPaths: Set<String> = ["/tmp/worktree"]

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        if shouldFailTrash {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "trash failed"])
        }
        trashedURLs.append(url)
    }
}

// MARK: - Worktree List Parsing Tests

@Suite
struct WorktreeManagerTests {

    private let mock: MockGitExecutor
    private let sut: WorktreeManager

    init() {
        mock = MockGitExecutor()
        sut = WorktreeManager(executor: mock)
    }

    @Test func listWorktrees_singleBranchWorktree_parsesCorrectly() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo
        HEAD abc1234567890abcdef
        branch refs/heads/main

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result.count == 1)
        #expect(result[0].path == "/Users/user/repo")
        #expect(result[0].folderName == "repo")
        #expect(result[0].branch == "main")
        #expect(result[0].commitHash == "abc1234567890abcdef")
        #expect(!result[0].isDetached)
        #expect(!result[0].isBare)
        #expect(!result[0].isLocked)
    }

    @Test func listWorktrees_branchWithRefsHeadsPrefix_stripsPrefix() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo/feature-branch
        HEAD deadbeef
        branch refs/heads/feature/my-feature

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result[0].branch == "feature/my-feature")
    }

    @Test func listWorktrees_branchWithoutRefsHeadsPrefix_keepsAsIs() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo
        HEAD deadbeef
        branch main

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result[0].branch == "main")
    }

    @Test func listWorktrees_detachedHead_setsIsDetached() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo/detached
        HEAD abc1234
        detached

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result.count == 1)
        #expect(result[0].isDetached)
        #expect(result[0].branch == nil)
    }

    @Test func listWorktrees_bareWorktree_setsIsBare() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo.git
        HEAD 0000000000000000000000000000000000000000
        bare

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result.count == 1)
        #expect(result[0].isBare)
    }

    @Test func listWorktrees_lockedWorktree_setsIsLocked() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo/locked-wt
        HEAD abc1234
        branch refs/heads/feature/locked
        locked reason for locking

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result.count == 1)
        #expect(result[0].isLocked)
    }

    @Test func listWorktrees_multipleWorktrees_parsesAll() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo
        HEAD abc1111
        branch refs/heads/main

        worktree /Users/user/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        worktree /Users/user/worktrees/feature-b
        HEAD abc3333
        detached

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result.count == 3)
        #expect(result[0].branch == "main")
        #expect(result[1].branch == "feature/a")
        #expect(result[2].isDetached)
    }

    @Test func listWorktrees_folderName_isLastPathComponent() async throws {
        mock.stub(stdout: """
        worktree /Users/user/oh-my-worktree/workspaces/my-repo/bright-ocean-widget
        HEAD abc1234
        branch refs/heads/feat/widget

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result[0].folderName == "bright-ocean-widget")
    }

    @Test func listWorktrees_emptyOutput_returnsEmpty() async throws {
        mock.stub(stdout: "")

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    @Test func listWorktrees_whitespaceOnlyOutput_returnsEmpty() async throws {
        mock.stub(stdout: "\n\n\n")

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    @Test func listWorktrees_nonZeroExitCode_throws() async {
        mock.stub(stdout: "", exitCode: 128)

        await #expect(throws: (any Error).self) {
            try await sut.listWorktrees(repositoryPath: "/tmp/repo")
        }
    }

    @Test func listWorktrees_executorThrows_rethrows() async {
        mock.stubError(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "process failed"]))

        await #expect(throws: (any Error).self) {
            try await sut.listWorktrees(repositoryPath: "/tmp/repo")
        }
    }

    @Test func listWorktrees_prunableWorktree_isExcluded() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo
        HEAD abc1111
        branch refs/heads/main

        worktree /Users/user/worktrees/stale-wt
        HEAD abc2222
        branch refs/heads/feature/stale
        prunable gitdir file points to non-existent location

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result.count == 1)
        #expect(result[0].branch == "main")
    }

    @Test func listWorktrees_prunableAmongMultiple_onlyExcludesPrunable() async throws {
        mock.stub(stdout: """
        worktree /Users/user/repo
        HEAD abc1111
        branch refs/heads/main

        worktree /Users/user/worktrees/good-wt
        HEAD abc2222
        branch refs/heads/feature/good

        worktree /Users/user/worktrees/stale-wt
        HEAD abc3333
        branch refs/heads/feature/stale
        prunable gitdir file points to non-existent location

        """)

        let result = try await sut.listWorktrees(repositoryPath: "/tmp/repo")

        #expect(result.count == 2)
        #expect(!result.contains { $0.folderName == "stale-wt" })
        #expect(result.contains { $0.folderName == "good-wt" })
    }

    @Test func gitPull_alreadyUpToDate_returnsAlreadyUpToDate() async throws {
        mock.stub(stdout: "Already up to date.\n")

        let result = try await sut.gitPull(worktreePath: "/tmp/repo")

        #expect(result.alreadyUpToDate)
        #expect(result.summary == "Already up to date.")
    }

    @Test func gitPull_withChanges_returnsSummaryLine() async throws {
        mock.stub(stdout: """
        remote: Counting objects: 5, done.
        Updating abc1234..def5678
        Fast-forward
        README.md | 2 +-
        3 files changed, 5 insertions(+), 2 deletions(-)

        """)

        let result = try await sut.gitPull(worktreePath: "/tmp/repo")

        #expect(!result.alreadyUpToDate)
        #expect(result.summary == "3 files changed, 5 insertions(+), 2 deletions(-)")
    }

    @Test func gitPull_conflictError_throws() async {
        mock.stub(stdout: "", exitCode: 1)
        mock.stubbedResult = CommandResult(stdout: "", stderr: "CONFLICT (content): Merge conflict in README.md", exitCode: 1)

        await #expect(throws: (any Error).self) {
            try await sut.gitPull(worktreePath: "/tmp/repo")
        }
    }
}

// MARK: - Quick Remove Worktree Tests

@Suite
struct WorktreeManagerQuickRemoveTests {

    private let mockExecutor: MockGitExecutor
    private let mockFileManager: MockFileManager
    private let sut: WorktreeManager

    init() {
        mockExecutor = MockGitExecutor()
        mockFileManager = MockFileManager()
        sut = WorktreeManager(executor: mockExecutor, fileManager: mockFileManager)
    }

    @Test func quickRemove_trashesDirectoryAndRunsPrune() async throws {
        try await sut.quickRemoveWorktree(
            worktreePath: "/tmp/worktree",
            repositoryPath: "/tmp/repo"
        )

        #expect(mockFileManager.trashedURLs.count == 1)
        #expect(mockFileManager.trashedURLs.first?.path == "/tmp/worktree")

        #expect(
            mockExecutor.executedCommands.contains(["worktree", "prune"])
        )
    }

    @Test func quickRemove_directoryNotExists_skipTrashAndPruneOnly() async throws {
        try await sut.quickRemoveWorktree(
            worktreePath: "/nonexistent/path/that/does/not/exist",
            repositoryPath: "/tmp/repo"
        )

        #expect(mockFileManager.trashedURLs.isEmpty)

        #expect(
            mockExecutor.executedCommands.contains(["worktree", "prune"])
        )
    }

    @Test func quickRemove_trashFailure_throwsError() async {
        mockFileManager.shouldFailTrash = true

        await #expect(throws: (any Error).self) {
            try await sut.quickRemoveWorktree(
                worktreePath: "/tmp/worktree",
                repositoryPath: "/tmp/repo"
            )
        }

        #expect(
            !mockExecutor.executedCommands.contains(["worktree", "prune"])
        )
    }

    @Test func fileExists_delegatesToInjectedFileManager() {
        #expect(sut.fileExists(atPath: "/tmp/worktree"))

        #expect(!sut.fileExists(atPath: "/nonexistent/path"))
    }

    @Test func fileExists_reflectsCustomExistingPaths() {
        mockFileManager.existingPaths = ["/custom/a", "/custom/b"]
        #expect(sut.fileExists(atPath: "/custom/a"))
        #expect(sut.fileExists(atPath: "/custom/b"))
        #expect(!sut.fileExists(atPath: "/custom/c"))
    }

    @Test func quickRemove_pruneFailure_doesNotThrowAfterSuccessfulTrash() async throws {
        mockExecutor.stubbedResult = CommandResult(stdout: "", stderr: "prune error", exitCode: 1)

        try await sut.quickRemoveWorktree(
            worktreePath: "/tmp/worktree",
            repositoryPath: "/tmp/repo"
        )

        #expect(mockFileManager.trashedURLs.count == 1)
        #expect(mockExecutor.executedCommands.contains(["worktree", "prune"]))
    }
}
