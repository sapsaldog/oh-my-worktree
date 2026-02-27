import Foundation

/// Fetches GitHub pull request information using the `gh` CLI.
/// Gracefully degrades when `gh` is not installed, not authenticated, or the repository is not on GitHub.
final class PullRequestService: @unchecked Sendable {

    private let gitExecutor: GitCommandExecuting
    private let ghCliPath: String?

    init(gitExecutor: GitCommandExecuting = GitCommandExecutor(), ghCliPath: String? = nil) {
        self.gitExecutor = gitExecutor
        self.ghCliPath = ghCliPath
    }

    // MARK: - Public API

    /// Fetches open pull requests for the given repository, returning a mapping of branch name to PR info.
    /// Returns an empty dictionary if `gh` is unavailable, the repo is not GitHub, or any error occurs.
    func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo] {
        guard let ghPath = ghCliPath ?? findGhCli() else { return [:] }
        guard await isGitHubRepository(repositoryPath: repositoryPath) else { return [:] }

        do {
            let result = try await gitExecutor.execute(
                command: ghPath,
                arguments: ["pr", "list", "--json", "number,url,headRefName", "--limit", "100"],
                workingDirectory: repositoryPath
            )

            guard result.exitCode == 0 else { return [:] }
            return parsePullRequests(from: result.stdout)
        } catch {
            return [:]
        }
    }

    // MARK: - Private Helpers

    /// Checks common paths for the `gh` CLI binary.
    private func findGhCli() -> String? {
        let paths = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Determines whether the repository's origin remote points to GitHub.
    private func isGitHubRepository(repositoryPath: String) async -> Bool {
        do {
            let result = try await gitExecutor.execute(
                command: "/usr/bin/git",
                arguments: ["config", "--get", "remote.origin.url"],
                workingDirectory: repositoryPath
            )
            guard result.exitCode == 0 else { return false }
            return result.stdout.contains("github.com")
        } catch {
            return false
        }
    }

    /// Parses the JSON output from `gh pr list` into a branch-keyed dictionary.
    private func parsePullRequests(from jsonString: String) -> [String: PullRequestInfo] {
        guard let data = jsonString.data(using: .utf8) else { return [:] }

        struct GhPullRequest: Decodable {
            let number: Int
            let url: String
            let headRefName: String
        }

        do {
            let prs = try JSONDecoder().decode([GhPullRequest].self, from: data)
            var result: [String: PullRequestInfo] = [:]
            for pr in prs {
                result[pr.headRefName] = PullRequestInfo(
                    number: pr.number,
                    url: pr.url,
                    branch: pr.headRefName
                )
            }
            return result
        } catch {
            return [:]
        }
    }
}
