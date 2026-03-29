import Foundation

// MARK: - Remote Operations & Git Queries

extension WorktreeManager {

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

    // MARK: - Fetch Pull Request Ref

    /// Fetches the head commit of a pull request by number using `pull/<number>/head`.
    /// Works for both same-repo and fork PRs.
    ///
    /// Returns a named ref (e.g. `refs/omw/pr/123`) that can be used as a stable
    /// start-point for `git worktree add`. Using a named ref instead of `FETCH_HEAD`
    /// avoids a race where an interleaving `git fetch` could overwrite `FETCH_HEAD`
    /// between the fetch and the worktree creation.
    /// Callers should delete the ref via `deleteRef(_:repositoryPath:)` after use.
    @discardableResult
    func fetchPullRequestRef(number: Int, repositoryPath: String) async throws -> String {
        let ref = "refs/omw/pr/\(number)"
        let result = try await executor.execute(
            arguments: ["fetch", "origin", "+pull/\(number)/head:\(ref)"],
            workingDirectory: repositoryPath
        )
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = stderr.isEmpty
                ? "Failed to fetch PR #\(number) from origin."
                : stderr
            throw OhMyWorktreeError.commandExecutionFailed(command: "git fetch", stderr: message)
        }
        return ref
    }

    /// Deletes a named ref created by `fetchPullRequestRef`. Best-effort: errors are ignored.
    func deleteRef(_ ref: String, repositoryPath: String) async {
        _ = try? await executor.execute(
            arguments: ["update-ref", "-d", ref],
            workingDirectory: repositoryPath
        )
    }

    // MARK: - Git Pull

    func gitPull(worktreePath: String) async throws -> GitPullResult {
        let result = try await executor.execute(
            arguments: ["pull"],
            workingDirectory: worktreePath
        )

        let stdout = result.stdout
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            // Git outputs "CONFLICT" markers to stdout, not stderr.
            if stdout.contains("CONFLICT") || stderr.contains("CONFLICT") {
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
}
