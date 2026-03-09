import Foundation

struct GitPullResult: Sendable {
    let alreadyUpToDate: Bool
    let summary: String
}

final class WorktreeManager: Sendable {
    private let executor: GitCommandExecuting

    init(executor: GitCommandExecuting = GitCommandExecutor()) {
        self.executor = executor
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
        let repoName = (repositoryPath as NSString).lastPathComponent
        let worktreePath = (NSHomeDirectory() as NSString)
            .appendingPathComponent("oh-my-worktree/workspaces/\(repoName)/\(folderName)")

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
        let repoName = (repositoryPath as NSString).lastPathComponent
        let worktreePath = (NSHomeDirectory() as NSString)
            .appendingPathComponent("oh-my-worktree/workspaces/\(repoName)/\(folderName)")

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

    // MARK: - Fetch Remote Branch

    func fetchBranch(_ branch: String, repositoryPath: String) async throws {
        let result = try await executor.execute(
            arguments: ["fetch", "origin", branch],
            workingDirectory: repositoryPath
        )
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let isNotFound = stderr.contains("couldn't find remote ref") ||
                             stderr.contains("does not appear to be a git repository")
            let message = isNotFound
                ? "Branch '\(branch)' was not found on the remote."
                : stderr.isEmpty ? "Failed to fetch branch '\(branch)' from origin." : stderr
            throw OhMyWorktreeError.commandExecutionFailed(command: "git fetch", stderr: message)
        }
    }

    // MARK: - Remove Worktree

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

    // MARK: - Git Pull

    func gitPull(worktreePath: String) async throws -> GitPullResult {
        let result = try await executor.execute(
            arguments: ["pull"],
            workingDirectory: worktreePath
        )

        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.contains("CONFLICT") {
                throw OhMyWorktreeError.commandExecutionFailed(
                    command: "git pull",
                    stderr: "Merge conflict detected. Please resolve conflicts manually."
                )
            }
            if stderr.contains("no tracking information") {
                throw OhMyWorktreeError.commandExecutionFailed(
                    command: "git pull",
                    stderr: "No upstream branch configured. Run 'git branch --set-upstream-to' in a terminal."
                )
            }
            if stderr.contains("local changes") && stderr.contains("overwritten") {
                throw OhMyWorktreeError.commandExecutionFailed(
                    command: "git pull",
                    stderr: "Uncommitted local changes would be overwritten. Please commit or stash your changes first."
                )
            }
            throw OhMyWorktreeError.commandExecutionFailed(
                command: "git pull",
                stderr: stderr
            )
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if output.contains("Already up to date") {
            return GitPullResult(alreadyUpToDate: true, summary: "Already up to date.")
        }

        // Parse the summary line like "3 files changed, 5 insertions(+), 2 deletions(-)"
        let lines = output.components(separatedBy: "\n")
        if let summaryLine = lines.last(where: {
            $0.contains("changed") || $0.contains("insertion") || $0.contains("deletion")
        }) {
            return GitPullResult(alreadyUpToDate: false, summary: summaryLine.trimmingCharacters(in: .whitespaces))
        }

        return GitPullResult(alreadyUpToDate: false, summary: output.components(separatedBy: "\n").last ?? "Pull completed.")
    }

    // MARK: - Validate Repository

    func isValidGitRepository(path: String) async -> Bool {
        do {
            let result = try await executor.execute(
                arguments: ["rev-parse", "--git-dir"],
                workingDirectory: path
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    // MARK: - Get Current Branch

    func getCurrentBranch(repositoryPath: String) async -> String? {
        do {
            let result = try await executor.execute(
                arguments: ["rev-parse", "--abbrev-ref", "HEAD"],
                workingDirectory: repositoryPath
            )
            guard result.exitCode == 0 else { return nil }
            let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return branch == "HEAD" ? nil : branch
        } catch {
            return nil
        }
    }

    // MARK: - List Branches

    func listBranches(repositoryPath: String) async throws -> [String] {
        let result = try await executor.execute(
            arguments: ["branch", "--format=%(refname:short)"],
            workingDirectory: repositoryPath
        )

        guard result.exitCode == 0 else {
            throw OhMyWorktreeError.commandExecutionFailed(
                command: "git branch",
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return result.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Last Commit Time

    func lastCommitDate(worktreePath: String) async -> Date? {
        do {
            let result = try await executor.execute(
                arguments: ["log", "-1", "--format=%ct"],
                workingDirectory: worktreePath
            )
            guard result.exitCode == 0 else { return nil }
            let timestamp = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let interval = TimeInterval(timestamp) else { return nil }
            return Date(timeIntervalSince1970: interval)
        } catch {
            return nil
        }
    }

    // MARK: - Parsing

    private func parseWorktreeList(_ output: String) -> [Worktree] {
        return output.components(separatedBy: "\n\n").compactMap { parseWorktreeBlock($0) }
    }

    private func parseWorktreeBlock(_ block: String) -> Worktree? {
        let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBlock.isEmpty else { return nil }

        let lines = trimmedBlock.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let parsed = parseWorktreeLines(lines)

        guard let worktreePath = parsed.path else { return nil }
        return Worktree(
            path: worktreePath,
            folderName: (worktreePath as NSString).lastPathComponent,
            branch: parsed.branch,
            commitHash: parsed.commitHash,
            isDetached: parsed.isDetached,
            isBare: parsed.isBare,
            isLocked: parsed.isLocked
        )
    }

    private func parseWorktreeLines(_ lines: [String]) -> WorktreeLineTokens {
        var path: String?
        var commitHash = ""
        var branch: String?
        var isDetached = false
        var isBare = false
        var isLocked = false

        for lineStr in lines {
            if lineStr.hasPrefix("worktree ") {
                path = String(lineStr.dropFirst("worktree ".count))
            } else if lineStr.hasPrefix("HEAD ") {
                commitHash = String(lineStr.dropFirst("HEAD ".count))
            } else if lineStr.hasPrefix("branch ") {
                let refPath = String(lineStr.dropFirst("branch ".count))
                branch = refPath.hasPrefix("refs/heads/")
                    ? String(refPath.dropFirst("refs/heads/".count))
                    : refPath
            } else if lineStr == "detached" {
                isDetached = true
            } else if lineStr == "bare" {
                isBare = true
            } else if lineStr.hasPrefix("locked") {
                isLocked = true
            }
        }

        return WorktreeLineTokens(
            path: path, commitHash: commitHash, branch: branch,
            isDetached: isDetached, isBare: isBare, isLocked: isLocked
        )
    }
}

private struct WorktreeLineTokens {
    let path: String?
    let commitHash: String
    let branch: String?
    let isDetached: Bool
    let isBare: Bool
    let isLocked: Bool
}
