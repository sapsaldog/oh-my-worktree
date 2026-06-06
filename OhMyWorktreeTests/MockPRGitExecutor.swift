import Foundation

@testable import OhMyWorktree

// MARK: - Shared mock for PullRequestService test suites
// Used by PullRequestServiceTests, PullRequestServiceListTests, and
// PullRequestServiceDiscoveryTests. Records (command, arguments) -> result
// expectations and returns a "not configured" failure for anything unstubbed.

final class MockGitCommandExecutor: GitCommandExecuting, @unchecked Sendable {
    var results: [(command: String, arguments: [String], result: Result<CommandResult, Error>)] = []

    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        for entry in results {
            if entry.command == command && entry.arguments == arguments {
                return try entry.result.get()
            }
        }
        return CommandResult(stdout: "", stderr: "not configured", exitCode: 1)
    }

    func stubGitConfig(remoteURL: String) {
        results.append((
            command: "/usr/bin/git",
            arguments: ["config", "--get", "remote.origin.url"],
            result: .success(CommandResult(stdout: remoteURL, stderr: "", exitCode: 0))
        ))
    }

    func stubGitConfigFailure() {
        results.append((
            command: "/usr/bin/git",
            arguments: ["config", "--get", "remote.origin.url"],
            result: .success(CommandResult(stdout: "", stderr: "error", exitCode: 1))
        ))
    }

    func stubGitConfigThrows() {
        results.append((
            command: "/usr/bin/git",
            arguments: ["config", "--get", "remote.origin.url"],
            result: .failure(NSError(domain: "test", code: 2,
                                     userInfo: [NSLocalizedDescriptionKey: "git exploded"]))
        ))
    }

    func stubGhPrList(json: String, ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: [
                "pr", "list",
                "--json", "number,url,headRefName,state,title,author,updatedAt,isDraft,reviewDecision,statusCheckRollup",
                "--state", "all", "--limit", "100"
            ],
            result: .success(CommandResult(stdout: json, stderr: "", exitCode: 0))
        ))
    }

    func stubGhPrListFailure(ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: [
                "pr", "list",
                "--json", "number,url,headRefName,state,title,author,updatedAt,isDraft,reviewDecision,statusCheckRollup",
                "--state", "all", "--limit", "100"
            ],
            result: .success(CommandResult(stdout: "", stderr: "error", exitCode: 1))
        ))
    }

    func stubGhPrListThrows(ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: [
                "pr", "list",
                "--json", "number,url,headRefName,state,title,author,updatedAt,isDraft,reviewDecision,statusCheckRollup",
                "--state", "all", "--limit", "100"
            ],
            result: .failure(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "connection failed"]))
        ))
    }

    // Stubs for fetchPullRequestList (FR-031)
    func stubGhPrListFull(json: String, ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: [
                "pr", "list", "--json",
                "number,url,headRefName,state,title,author,updatedAt,isDraft",
                "--state", "all", "--limit", "100"
            ],
            result: .success(CommandResult(stdout: json, stderr: "", exitCode: 0))
        ))
    }

    func stubGhPrListFullFailure(ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: [
                "pr", "list", "--json",
                "number,url,headRefName,state,title,author,updatedAt,isDraft",
                "--state", "all", "--limit", "100"
            ],
            result: .success(CommandResult(stdout: "", stderr: "error", exitCode: 1))
        ))
    }
}
