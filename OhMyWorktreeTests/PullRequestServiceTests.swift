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
            arguments: ["pr", "list", "--json", "number,url,headRefName,state", "--state", "all", "--limit", "100"],
            result: .success(CommandResult(stdout: json, stderr: "", exitCode: 0))
        ))
    }

    func stubGhPrListFailure(ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: ["pr", "list", "--json", "number,url,headRefName,state", "--state", "all", "--limit", "100"],
            result: .success(CommandResult(stdout: "", stderr: "error", exitCode: 1))
        ))
    }

    func stubGhPrListThrows(ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: ["pr", "list", "--json", "number,url,headRefName,state", "--state", "all", "--limit", "100"],
            result: .failure(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "connection failed"]))
        ))
    }

    // Stubs for fetchPullRequestList (FR-031)
    func stubGhPrListFull(json: String, ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: ["pr", "list", "--json", "number,url,headRefName,state,title,author,updatedAt,isDraft", "--state", "all", "--limit", "100"],
            result: .success(CommandResult(stdout: json, stderr: "", exitCode: 0))
        ))
    }

    func stubGhPrListFullFailure(ghPath: String = "/usr/local/bin/gh") {
        results.append((
            command: ghPath,
            arguments: ["pr", "list", "--json", "number,url,headRefName,state,title,author,updatedAt,isDraft", "--state", "all", "--limit", "100"],
            result: .success(CommandResult(stdout: "", stderr: "error", exitCode: 1))
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
            {"number": 42, "url": "https://github.com/user/repo/pull/42", "headRefName": "feature/login", "state": "OPEN"},
            {"number": 99, "url": "https://github.com/user/repo/pull/99", "headRefName": "fix/crash", "state": "MERGED"}
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
        XCTAssertEqual(loginPR?.state, .open)

        let crashPR = result["fix/crash"]
        XCTAssertNotNil(crashPR)
        XCTAssertEqual(crashPR?.number, 99)
        XCTAssertEqual(crashPR?.state, .merged)
    }

    func testFetchPullRequests_withSinglePR_returnsOnePR() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "https://github.com/user/repo.git")
        mock.stubGhPrList(json: """
        [{"number": 1, "url": "https://github.com/user/repo/pull/1", "headRefName": "main-patch", "state": "OPEN"}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["main-patch"]?.number, 1)
        XCTAssertEqual(result["main-patch"]?.state, .open)
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

    func testFetchPullRequests_duplicateBranch_mostRecentWins() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        // gh pr list returns most recent first
        mock.stubGhPrList(json: """
        [
            {"number": 1, "url": "https://github.com/user/repo/pull/1", "headRefName": "feature/x", "state": "CLOSED"},
            {"number": 2, "url": "https://github.com/user/repo/pull/2", "headRefName": "feature/x", "state": "MERGED"}
        ]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["feature/x"]?.number, 1)
    }

    func testFetchPullRequests_duplicateBranch_openTakesPriority() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: """
        [
            {"number": 1, "url": "https://github.com/user/repo/pull/1", "headRefName": "feature/x", "state": "OPEN"},
            {"number": 2, "url": "https://github.com/user/repo/pull/2", "headRefName": "feature/x", "state": "CLOSED"}
        ]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["feature/x"]?.number, 1)
        XCTAssertEqual(result["feature/x"]?.state, .open)
    }

    func testFetchPullRequests_withMissingState_defaultsToOpen() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: """
        [{"number": 5, "url": "https://github.com/user/repo/pull/5", "headRefName": "legacy"}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["legacy"]?.state, .open)
    }

    // MARK: - HTTPS Remote URL

    func testFetchPullRequests_withHTTPSGitHubRemote_succeeds() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "https://github.com/user/repo.git")
        mock.stubGhPrList(json: """
        [{"number": 10, "url": "https://github.com/user/repo/pull/10", "headRefName": "dev", "state": "OPEN"}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["dev"]?.number, 10)
    }

    // MARK: - isGitHubAvailable (FR-031)

    func testIsGitHubAvailable_withGitHubRemote_returnsTrue() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        // Use /bin/sh as a stand-in for an executable gh CLI (always present on macOS)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: "/bin/sh")

        let result = await sut.isGitHubAvailable(repositoryPath: "/tmp/repo")

        XCTAssertTrue(result)
    }

    func testIsGitHubAvailable_withNonGitHubRemote_returnsFalse() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@gitlab.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: "/bin/sh")

        let result = await sut.isGitHubAvailable(repositoryPath: "/tmp/repo")

        XCTAssertFalse(result)
    }

    func testIsGitHubAvailable_withNoGhCli_returnsFalse() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: "/nonexistent/gh")

        let result = await sut.isGitHubAvailable(repositoryPath: "/tmp/repo")

        XCTAssertFalse(result)
    }

    // MARK: - fetchPullRequestList (FR-031)

    func testFetchPullRequestList_withValidJSON_parsesAllFields() async throws {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: """
        [{
            "number": 42,
            "url": "https://github.com/user/repo/pull/42",
            "headRefName": "feature/dark-mode",
            "state": "OPEN",
            "title": "Add dark mode support",
            "author": {"login": "alice"},
            "updatedAt": "2024-01-15T10:30:00Z",
            "isDraft": false
        }]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let rawResult = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")
        let result = try XCTUnwrap(rawResult)

        XCTAssertEqual(result.count, 1)
        let pr = result[0]
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.branch, "feature/dark-mode")
        XCTAssertEqual(pr.title, "Add dark mode support")
        XCTAssertEqual(pr.author, "alice")
        XCTAssertEqual(pr.state, .open)
        XCTAssertFalse(pr.isDraft)
        XCTAssertNotNil(pr.updatedAt)
    }

    func testFetchPullRequestList_withDraftPR_setsDraftFlag() async throws {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: """
        [{
            "number": 7,
            "url": "https://github.com/user/repo/pull/7",
            "headRefName": "wip/feature",
            "state": "OPEN",
            "title": "WIP: new feature",
            "author": {"login": "bob"},
            "updatedAt": null,
            "isDraft": true
        }]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let rawResult = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")
        let result = try XCTUnwrap(rawResult)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isDraft)
    }

    func testFetchPullRequestList_withMissingAuthor_usesEmptyString() async throws {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: """
        [{
            "number": 1,
            "url": "https://github.com/user/repo/pull/1",
            "headRefName": "main",
            "state": "OPEN",
            "title": "No author",
            "updatedAt": null,
            "isDraft": false
        }]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let rawResult = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")
        let result = try XCTUnwrap(rawResult)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].author, "")
    }

    func testFetchPullRequestList_preservesOrder() async throws {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: """
        [
            {"number": 10, "url": "https://github.com/user/repo/pull/10", "headRefName": "a", "state": "OPEN", "title": "A", "author": {"login": "a"}, "updatedAt": null, "isDraft": false},
            {"number": 5,  "url": "https://github.com/user/repo/pull/5",  "headRefName": "b", "state": "OPEN", "title": "B", "author": {"login": "b"}, "updatedAt": null, "isDraft": false}
        ]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let rawResult = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")
        let result = try XCTUnwrap(rawResult)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].number, 10)
        XCTAssertEqual(result[1].number, 5)
    }

    func testFetchPullRequestList_withNonGitHubRemote_returnsNil() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@gitlab.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")

        XCTAssertNil(result)
    }

    func testFetchPullRequestList_withNoGhCli_returnsNil() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: "/nonexistent/gh")

        let result = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")

        XCTAssertNil(result)
    }

    func testFetchPullRequestList_withCommandFailure_returnsNil() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFullFailure()
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")

        XCTAssertNil(result)
    }

    func testFetchPullRequestList_withInvalidJSON_returnsNil() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: "not json")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")

        XCTAssertNil(result)
    }
}
