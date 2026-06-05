import Foundation

protocol PullRequestFetching: Sendable {
    func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo]
    func isGitHubAvailable(repositoryPath: String) async -> Bool
    /// Returns the full PR list, or `nil` on any error (gh unavailable, not GitHub, command failed, parse error).
    /// An empty array means success with zero PRs.
    func fetchPullRequestList(repositoryPath: String) async -> [PullRequestInfo]?
}

extension PullRequestFetching {
    func isGitHubAvailable(repositoryPath: String) async -> Bool { false }
    func fetchPullRequestList(repositoryPath: String) async -> [PullRequestInfo]? { nil }
}

/// Fetches GitHub pull request information using the `gh` CLI.
/// Gracefully degrades when `gh` is not installed, not authenticated, or the repository is not on GitHub.
final class PullRequestService: PullRequestFetching, Sendable {

    private let gitExecutor: GitCommandExecuting
    /// Resolved once at init to avoid repeated filesystem checks and `which` subprocess spawns.
    private let resolvedGhCliPath: String?

    /// - Parameters:
    ///   - ghCliPath: an explicit `gh` path; when `nil`, `ghCliResolver` runs.
    ///   - ghCliResolver: resolves the `gh` path when none is supplied. Defaults
    ///     to the real `findGhCli`; tests inject a resolver (e.g. one returning
    ///     `nil`) to drive the "gh not found" branch deterministically. Production
    ///     supplies neither argument, so its behavior is unchanged.
    init(
        gitExecutor: GitCommandExecuting = GitCommandExecutor(),
        ghCliPath: String? = nil,
        ghCliResolver: () -> String? = { PullRequestService.findGhCli() }
    ) {
        self.gitExecutor = gitExecutor
        self.resolvedGhCliPath = ghCliPath ?? ghCliResolver()
    }

    // MARK: - Public API

    /// Fetches pull requests (open, merged, closed) for the given repository, returning a mapping of branch name to PR info.
    /// Returns an empty dictionary if `gh` is unavailable, the repo is not GitHub, or any error occurs.
    /// Note: Limited to the 100 most recent PRs across all states.
    func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo] {
        guard let ghPath = resolvedGhCliPath else {
            AppLog.debug("gh CLI not found, skipping PR fetch", category: "PullRequestService")
            return [:]
        }
        guard await isGitHubRepository(repositoryPath: repositoryPath) else { return [:] }

        do {
            let result = try await gitExecutor.execute(
                command: ghPath,
                arguments: ["pr", "list", "--json", "number,url,headRefName,state", "--state", "all", "--limit", "100"],
                workingDirectory: repositoryPath
            )

            guard result.exitCode == 0 else {
                AppLog.debug("gh pr list failed with exit code \(result.exitCode)", category: "PullRequestService")
                return [:]
            }
            return parsePullRequests(from: result.stdout)
        } catch {
            AppLog.debug("Failed to fetch PRs: \(error.localizedDescription)", category: "PullRequestService")
            return [:]
        }
    }

    /// Returns true when the `gh` CLI is installed and the repository is hosted on GitHub.
    /// Validates that the resolved gh path actually exists on disk (unlike fetchPullRequests,
    /// which defers failure to the command execution layer).
    func isGitHubAvailable(repositoryPath: String) async -> Bool {
        guard let path = resolvedGhCliPath,
              FileManager.default.isExecutableFile(atPath: path) else { return false }
        return await isGitHubRepository(repositoryPath: repositoryPath)
    }

    /// Fetches all PRs (open, draft, merged, closed) as an ordered array with full metadata.
    /// Returns `nil` on any error; returns an empty array when there are genuinely no PRs.
    func fetchPullRequestList(repositoryPath: String) async -> [PullRequestInfo]? {
        guard let ghPath = resolvedGhCliPath else { return nil }
        guard await isGitHubRepository(repositoryPath: repositoryPath) else { return nil }

        do {
            let result = try await gitExecutor.execute(
                command: ghPath,
                arguments: [
                    "pr", "list",
                    "--json", "number,url,headRefName,state,title,author,updatedAt,isDraft",
                    "--state", "all",
                    "--limit", "100"
                ],
                workingDirectory: repositoryPath
            )
            guard result.exitCode == 0 else { return nil }
            return parsePullRequestList(from: result.stdout)
        } catch {
            AppLog.debug("Failed to fetch PR list: \(error.localizedDescription)", category: "PullRequestService")
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Checks common paths for the `gh` CLI binary, then falls back to `which`
    /// so installs via nix, asdf, mise, etc. are discovered.
    /// - Parameter commonPaths: hardcoded locations to probe before falling back
    ///   to `PATH`. Defaults to the real list; tests override it so the `which`
    ///   fallback can be exercised deterministically regardless of the host.
    ///   Production calls this with no argument, so its behavior is unchanged.
    static func findGhCli(
        commonPaths: [String] = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]
    ) -> String? {
        if let found = commonPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        return resolveFromPath("gh")
    }

    /// Runs `/usr/bin/which` to resolve a command from the system PATH.
    /// - Parameter whichPath: the `which` executable to spawn. Defaults to the
    ///   real `/usr/bin/which`; tests override it (e.g. with a missing path) to
    ///   exercise the spawn-failure branch. Production passes no argument, so its
    ///   behavior is unchanged.
    static func resolveFromPath(_ command: String, whichPath: String = "/usr/bin/which") -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: whichPath)
        process.arguments = [command]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return path
        } catch {
            return nil
        }
    }

    /// Determines whether the repository's origin remote points to GitHub.
    /// Note: Only supports github.com; GitHub Enterprise instances are not detected.
    private func isGitHubRepository(repositoryPath: String) async -> Bool {
        do {
            let result = try await gitExecutor.execute(
                command: "/usr/bin/git",
                arguments: ["config", "--get", "remote.origin.url"],
                workingDirectory: repositoryPath
            )
            guard result.exitCode == 0 else { return false }
            let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return url.contains("github.com:") || url.contains("github.com/")
        } catch {
            return false
        }
    }

    /// Shared formatters — `ISO8601DateFormatter` is expensive to initialize.
    /// GitHub's `updatedAt` typically includes fractional seconds (e.g. "2024-01-15T10:30:00.000Z"),
    /// but we keep a fallback for dates without them since the format isn't guaranteed.
    nonisolated(unsafe) private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoFormatterWithoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parses the rich JSON output from `gh pr list` (with title, author, updatedAt, isDraft) into an array.
    /// Returns `nil` on parse error; returns an empty array when the JSON array is empty.
    private func parsePullRequestList(from jsonString: String) -> [PullRequestInfo]? {
        guard let data = jsonString.data(using: .utf8) else { return nil }

        struct GhPR: Decodable {
            let number: Int
            let url: String
            let headRefName: String
            let state: String?
            let title: String
            let author: GhAuthor?
            let updatedAt: String?
            let isDraft: Bool?

            struct GhAuthor: Decodable { let login: String }
        }

        do {
            let prs = try JSONDecoder().decode([GhPR].self, from: data)
            return prs.compactMap { pr in
                guard let url = URL(string: pr.url) else { return nil }
                let state = pr.state.flatMap { PullRequestState(rawValue: $0) } ?? .open
                let updatedAt = pr.updatedAt.flatMap {
                    Self.isoFormatterWithFractional.date(from: $0) ?? Self.isoFormatterWithoutFractional.date(from: $0)
                }
                return PullRequestInfo(
                    number: pr.number,
                    url: url,
                    branch: pr.headRefName,
                    state: state,
                    title: pr.title,
                    author: pr.author?.login ?? "",
                    updatedAt: updatedAt,
                    isDraft: pr.isDraft ?? false
                )
            }
        } catch {
            AppLog.debug("Failed to parse PR list JSON: \(error.localizedDescription)", category: "PullRequestService")
            return nil
        }
    }

    /// Parses the JSON output from `gh pr list` into a branch-keyed dictionary.
    /// When multiple PRs exist for the same branch, open PRs take priority; otherwise the most recent one wins.
    private func parsePullRequests(from jsonString: String) -> [String: PullRequestInfo] {
        guard let data = jsonString.data(using: .utf8) else { return [:] }

        struct GhPullRequest: Decodable {
            let number: Int
            let url: String
            let headRefName: String
            let state: String?
        }

        do {
            let prs = try JSONDecoder().decode([GhPullRequest].self, from: data)
            var result: [String: PullRequestInfo] = [:]
            for pr in prs {
                guard let url = URL(string: pr.url) else { continue }
                let state = pr.state.flatMap { PullRequestState(rawValue: $0) } ?? .open
                let info = PullRequestInfo(
                    number: pr.number,
                    url: url,
                    branch: pr.headRefName,
                    state: state
                )
                // gh returns PRs in reverse-chronological order, so the first entry per branch
                // is the most recent. Preserve it in two cases:
                //   1. The existing PR is open — open PRs always take priority.
                //   2. The new PR is not open — never replace with a closed/merged PR.
                // In other words, we only overwrite when existing is non-open AND the new one is open.
                if let existing = result[pr.headRefName] {
                    if existing.state == .open || info.state != .open {
                        continue
                    }
                }
                result[pr.headRefName] = info
            }
            return result
        } catch {
            AppLog.debug("Failed to parse PR JSON: \(error.localizedDescription)", category: "PullRequestService")
            return [:]
        }
    }
}
