import XCTest

@testable import OhMyWorktree

// MARK: - Mock

private final class MockGitCommandExecutor: GitCommandExecuting, @unchecked Sendable {
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

    func stubGhPrList(json: String, ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: ["pr", "list", "--json", "number,url,headRefName", "--limit", "100"],
            result: .success(CommandResult(stdout: json, stderr: "", exitCode: 0))
        ))
    }

    func stubGhPrListFailure(ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: ["pr", "list", "--json", "number,url,headRefName", "--limit", "100"],
            result: .success(CommandResult(stdout: "", stderr: "error", exitCode: 1))
        ))
    }

    func stubGhPrListThrows(ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: ["pr", "list", "--json", "number,url,headRefName", "--limit", "100"],
            result: .failure(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "connection failed"]))
        ))
    }
}

// MARK: - Tests

final class PullRequestServiceTests: XCTestCase {

    private let ghPath = "/usr/local/bin/gh"

    // MARK: - Successful Fetch

    func testFetchPullRequests_withValidJSON_returnsMappedPRs() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: """
        [
            {"number": 42, "url": "https://github.com/user/repo/pull/42", "headRefName": "feature/login"},
            {"number": 99, "url": "https://github.com/user/repo/pull/99", "headRefName": "fix/crash"}
        ]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 2)

        let loginPR = result["feature/login"]
        XCTAssertNotNil(loginPR)
        XCTAssertEqual(loginPR?.number, 42)
        XCTAssertEqual(loginPR?.url, URL(string: "https://github.com/user/repo/pull/42"))
        XCTAssertEqual(loginPR?.branch, "feature/login")

        let crashPR = result["fix/crash"]
        XCTAssertNotNil(crashPR)
        XCTAssertEqual(crashPR?.number, 99)
    }

    func testFetchPullRequests_withSinglePR_returnsOnePR() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "https://github.com/user/repo.git")
        mock.stubGhPrList(json: """
        [{"number": 1, "url": "https://github.com/user/repo/pull/1", "headRefName": "main-patch"}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["main-patch"]?.number, 1)
    }

    func testFetchPullRequests_withEmptyArray_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: "[]")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - GitHub Detection

    func testFetchPullRequests_withNonGitHubRemote_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@gitlab.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    func testFetchPullRequests_withBitbucketRemote_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@bitbucket.org:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    func testFetchPullRequests_withGitConfigFailure_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfigFailure()
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - gh CLI Missing

    func testFetchPullRequests_withNonExistentGhPath_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: "/nonexistent/path/to/gh")

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - gh Command Failures

    func testFetchPullRequests_withNonZeroExitCode_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFailure()
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    func testFetchPullRequests_whenExecutorThrows_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListThrows()
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Invalid JSON

    func testFetchPullRequests_withInvalidJSON_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: "not valid json")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    func testFetchPullRequests_withMissingFields_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: """
        [{"number": 1}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    func testFetchPullRequests_withEmptyString_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: "")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Branch Mapping

    func testFetchPullRequests_duplicateBranch_lastOneWins() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: """
        [
            {"number": 1, "url": "https://github.com/user/repo/pull/1", "headRefName": "feature/x"},
            {"number": 2, "url": "https://github.com/user/repo/pull/2", "headRefName": "feature/x"}
        ]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["feature/x"]?.number, 2)
    }

    // MARK: - HTTPS Remote URL

    func testFetchPullRequests_withHTTPSGitHubRemote_succeeds() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "https://github.com/user/repo.git")
        mock.stubGhPrList(json: """
        [{"number": 10, "url": "https://github.com/user/repo/pull/10", "headRefName": "dev"}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["dev"]?.number, 10)
    }
}
