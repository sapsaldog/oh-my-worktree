import CryptoKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.ohmyworktree", category: "WorktreeManager")

struct GitPullResult: Sendable {
    let alreadyUpToDate: Bool
    let summary: String
}

/// Abstraction over FileManager for testability (trash operations).
protocol FileManaging: Sendable {
    func fileExists(atPath path: String) -> Bool
    func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws
}

extension FileManager: FileManaging, @unchecked Sendable {}

final class WorktreeManager: Sendable {
    let executor: GitCommandExecuting
    let fileManager: FileManaging

    init(executor: GitCommandExecuting = GitCommandExecutor(), fileManager: FileManaging = FileManager.default) {
        self.executor = executor
        self.fileManager = fileManager
    }

    /// Delegates to the injected `FileManaging` instance for file existence checks.
    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    // MARK: - Path Construction

    /// Canonical worktree directory path for a given repository and folder name.
    /// Used by both WorktreeManager and WorktreeListViewModel to avoid path divergence.
    /// Uses a SHA-256 hash suffix when the repo name alone would collide (e.g. two repos named "myapp").
    static func worktreePath(repositoryPath: String, folderName: String) -> String {
        let repoName = (repositoryPath as NSString).lastPathComponent
        // Include a deterministic hash of the full path to prevent collisions when
        // two repositories share the same directory name (e.g. /work/myapp and /personal/myapp).
        // Uses SHA-256 (not String.hashValue) because hashValue is randomized per process.
        let digest = SHA256.hash(data: Data(repositoryPath.utf8))
        let pathHash = digest.prefix(3).map { String(format: "%02x", $0) }.joined()
        let workspaceName = "\(repoName)-\(pathHash)"
        return (NSHomeDirectory() as NSString)
            .appendingPathComponent("oh-my-worktree/workspaces/\(workspaceName)/\(folderName)")
    }

    // MARK: - List Worktrees

    func listWorktrees(repositoryPath: String) async throws -> [Worktree] {
        let result = try await executor.execute(
            arguments: ["worktree", "list", "--porcelain"],
            workingDirectory: repositoryPath
        )

        guard result.exitCode == 0 else {
            throw OhMyWorktreeError.commandExecutionFailed(
                command: "git worktree list",
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return parseWorktreeList(result.stdout)
    }

    // MARK: - Add Worktree (new branch)

    func addWorktree(
        repositoryPath: String,
        folderName: String,
        baseBranch: String? = nil
    ) async throws -> Worktree {
        let worktreePath = Self.worktreePath(repositoryPath: repositoryPath, folderName: folderName)

        try FileManager.default.createDirectory(
            atPath: (worktreePath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        var arguments = ["worktree", "add", "-b", folderName, worktreePath]
        if let baseBranch {
            arguments.append(baseBranch)
        }

        let result = try await executor.execute(
            arguments: arguments,
            workingDirectory: repositoryPath
        )

        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.contains("already exists") {
                throw OhMyWorktreeError.worktreeAlreadyExists(branch: folderName)
            }
            throw OhMyWorktreeError.commandExecutionFailed(
                command: "git worktree add",
                stderr: stderr
            )
        }

        // Fetch fresh worktree list to return the newly created one
        let worktrees = try await listWorktrees(repositoryPath: repositoryPath)
        guard let newWorktree = worktrees.first(where: { $0.path == worktreePath }) else {
            throw OhMyWorktreeError.worktreeNotFound(path: worktreePath)
        }

        return newWorktree
    }

    // MARK: - Add Worktree (existing branch)

    func addWorktreeFromExistingBranch(
        repositoryPath: String,
        folderName: String,
        branch: String
    ) async throws -> Worktree {
        let worktreePath = Self.worktreePath(repositoryPath: repositoryPath, folderName: folderName)

        try FileManager.default.createDirectory(
            atPath: (worktreePath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        let arguments = ["worktree", "add", worktreePath, branch]

        let result = try await executor.execute(
            arguments: arguments,
            workingDirectory: repositoryPath
        )

        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.contains("already exists") {
                throw OhMyWorktreeError.worktreeAlreadyExists(branch: branch)
            }
            throw OhMyWorktreeError.commandExecutionFailed(
                command: "git worktree add",
                stderr: stderr
            )
        }

        let worktrees = try await listWorktrees(repositoryPath: repositoryPath)
        guard let newWorktree = worktrees.first(where: { $0.path == worktreePath }) else {
            throw OhMyWorktreeError.worktreeNotFound(path: worktreePath)
        }

        return newWorktree
    }

    // MARK: - Add Worktree (new local branch from remote)

    /// Creates a worktree with a brand-new local branch (`localBranch`) starting at
    /// the given `startPoint` (defaults to `origin/<remoteBranch>`).
    func addWorktreeFromRemoteBranch(
        repositoryPath: String,
        folderName: String,
        localBranch: String,
        remoteBranch: String,
        startPoint: String? = nil
    ) async throws -> Worktree {
        let worktreePath = Self.worktreePath(repositoryPath: repositoryPath, folderName: folderName)

        try FileManager.default.createDirectory(
            atPath: (worktreePath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        let resolvedStartPoint = startPoint ?? "origin/\(remoteBranch)"
        // Use -b (not -B) to prevent silently resetting an existing local branch
        // that has unpushed commits. If the branch already exists, git will fail
        // with a clear error rather than force-moving the branch pointer.
        let arguments = ["worktree", "add", "-b", localBranch, worktreePath, resolvedStartPoint]

        let result = try await executor.execute(
            arguments: arguments,
            workingDirectory: repositoryPath
        )

        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw OhMyWorktreeError.commandExecutionFailed(command: "git worktree add", stderr: stderr)
        }

        let worktrees = try await listWorktrees(repositoryPath: repositoryPath)
        guard let newWorktree = worktrees.first(where: { $0.path == worktreePath }) else {
            throw OhMyWorktreeError.worktreeNotFound(path: worktreePath)
        }

        return newWorktree
    }

    // MARK: - Remove / Prune Worktrees

    func removeWorktree(repositoryPath: String, worktreePath: String, force: Bool = false) async throws {
        var arguments = ["worktree", "remove", worktreePath]
        if force {
            arguments.insert("--force", at: 2)
        }

        let result = try await executor.execute(
            arguments: arguments,
            workingDirectory: repositoryPath
        )

        guard result.exitCode == 0 else {
            throw OhMyWorktreeError.commandExecutionFailed(
                command: "git worktree remove",
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    /// Moves the worktree directory to macOS Trash, then runs `git worktree prune`
    /// to clean up git metadata. Much faster than `git worktree remove` for projects
    /// with large directories (e.g. node_modules).
    ///
    /// Unlike `git worktree remove`, this does **not** check for uncommitted changes.
    /// The directory can be recovered from Trash, but the git worktree registration
    /// will already be pruned — manual `git worktree add` is needed after restoration.
    /// Prune errors are treated as non-fatal since the critical operation (trash) already succeeded.
    func quickRemoveWorktree(worktreePath: String, repositoryPath: String) async throws {
        if fileManager.fileExists(atPath: worktreePath) {
            let url = URL(fileURLWithPath: worktreePath)
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        }
        do {
            try await pruneWorktrees(repositoryPath: repositoryPath)
        } catch {
            logger.warning("git worktree prune failed after quick remove (non-fatal): \(error.localizedDescription)")
        }
    }

    /// Runs `git worktree prune` to remove administrative files for worktrees
    /// whose directories no longer exist on disk (e.g. manually deleted).
    func pruneWorktrees(repositoryPath: String) async throws {
        let result = try await executor.execute(
            arguments: ["worktree", "prune"],
            workingDirectory: repositoryPath
        )
        guard result.exitCode == 0 else {
            throw OhMyWorktreeError.commandExecutionFailed(
                command: "git worktree prune",
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

}
