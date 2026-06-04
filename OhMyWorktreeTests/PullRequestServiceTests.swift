import Foundation
import Testing

@testable import OhMyWorktree

// Tests for `PullRequestService.fetchPullRequests` (branch-keyed dictionary),
// GitHub detection, gh-availability, and protocol-extension defaults.
// The shared MockGitCommandExecutor lives in MockPRGitExecutor.swift.
// `fetchPullRequestList` tests live in PullRequestServiceListTests.swift;
// gh-CLI discovery tests live in PullRequestServiceDiscoveryTests.swift.
@Suite struct PullRequestServiceTests {

    private let ghPath = "/usr/local/bin/gh"

    // MARK: - Successful Fetch

    @Test func fetchPullRequests_withValidJSON_returnsMappedPRs() async {
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

        #expect(result.count == 2)

        let loginPR = result["feature/login"]
        #expect(loginPR != nil)
        #expect(loginPR?.number == 42)
        #expect(loginPR?.url == URL(string: "https://github.com/user/repo/pull/42"))
        #expect(loginPR?.branch == "feature/login")
        #expect(loginPR?.state == .open)

        let crashPR = result["fix/crash"]
        #expect(crashPR != nil)
        #expect(crashPR?.number == 99)
        #expect(crashPR?.state == .merged)
    }

    @Test func fetchPullRequests_withSinglePR_returnsOnePR() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "https://github.com/user/repo.git")
        mock.stubGhPrList(json: """
        [{"number": 1, "url": "https://github.com/user/repo/pull/1", "headRefName": "main-patch", "state": "OPEN"}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.count == 1)
        #expect(result["main-patch"]?.number == 1)
        #expect(result["main-patch"]?.state == .open)
    }

    @Test func fetchPullRequests_withEmptyArray_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: "[]")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    // MARK: - GitHub Detection

    @Test func fetchPullRequests_withNonGitHubRemote_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@gitlab.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    @Test func fetchPullRequests_withBitbucketRemote_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@bitbucket.org:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    @Test func fetchPullRequests_withGitConfigFailure_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfigFailure()
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    // MARK: - gh CLI Missing

    @Test func fetchPullRequests_withNonExistentGhPath_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: "/nonexistent/path/to/gh")

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    // Resolver returns nil -> resolvedGhCliPath is nil -> the "gh not found"
    // guard branch of fetchPullRequests runs (deterministic, no real gh).
    @Test func fetchPullRequests_whenGhUnresolved_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliResolver: { nil })

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    // MARK: - gh Command Failures

    @Test func fetchPullRequests_withNonZeroExitCode_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFailure()
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    @Test func fetchPullRequests_whenExecutorThrows_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListThrows()
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    // MARK: - Invalid JSON

    @Test func fetchPullRequests_withInvalidJSON_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: "not valid json")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    @Test func fetchPullRequests_withMissingFields_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: """
        [{"number": 1}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    @Test func fetchPullRequests_withEmptyString_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: "")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    // MARK: - Branch Mapping

    @Test func fetchPullRequests_duplicateBranch_mostRecentWins() async {
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

        #expect(result.count == 1)
        #expect(result["feature/x"]?.number == 1)
    }

    @Test func fetchPullRequests_duplicateBranch_openTakesPriority() async {
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

        #expect(result.count == 1)
        #expect(result["feature/x"]?.number == 1)
        #expect(result["feature/x"]?.state == .open)
    }

    @Test func fetchPullRequests_withMissingState_defaultsToOpen() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrList(json: """
        [{"number": 5, "url": "https://github.com/user/repo/pull/5", "headRefName": "legacy"}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.count == 1)
        #expect(result["legacy"]?.state == .open)
    }

    // MARK: - HTTPS Remote URL

    @Test func fetchPullRequests_withHTTPSGitHubRemote_succeeds() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "https://github.com/user/repo.git")
        mock.stubGhPrList(json: """
        [{"number": 10, "url": "https://github.com/user/repo/pull/10", "headRefName": "dev", "state": "OPEN"}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.count == 1)
        #expect(result["dev"]?.number == 10)
    }

    // MARK: - isGitHubAvailable (FR-031)

    @Test func isGitHubAvailable_withGitHubRemote_returnsTrue() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        // Use /bin/sh as a stand-in for an executable gh CLI (always present on macOS)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: "/bin/sh")

        let result = await sut.isGitHubAvailable(repositoryPath: "/tmp/repo")

        #expect(result)
    }

    @Test func isGitHubAvailable_withNonGitHubRemote_returnsFalse() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@gitlab.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: "/bin/sh")

        let result = await sut.isGitHubAvailable(repositoryPath: "/tmp/repo")

        #expect(false == result)
    }

    @Test func isGitHubAvailable_withNoGhCli_returnsFalse() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: "/nonexistent/gh")

        let result = await sut.isGitHubAvailable(repositoryPath: "/tmp/repo")

        #expect(false == result)
    }

    // MARK: - isGitHubRepository error path

    @Test func fetchPullRequests_whenGitConfigThrows_returnsEmpty() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfigThrows()
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    @Test func isGitHubAvailable_whenGitConfigThrows_returnsFalse() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfigThrows()
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: "/bin/sh")

        let result = await sut.isGitHubAvailable(repositoryPath: "/tmp/repo")

        #expect(false == result)
    }

    // MARK: - PullRequestFetching protocol-extension defaults

    /// A conformer that implements only the required method, so the
    /// `fetchPullRequestList` / `isGitHubAvailable` protocol-extension defaults apply.
    private struct DefaultOnlyFetcher: PullRequestFetching {
        func fetchPullRequests(repositoryPath: String) async -> [String: PullRequestInfo] { [:] }
    }

    @Test func protocolDefault_fetchPullRequestList_returnsNil() async {
        let fetcher = DefaultOnlyFetcher()
        let result = await fetcher.fetchPullRequestList(repositoryPath: "/tmp/repo")
        #expect(result == nil)
    }

    @Test func protocolDefault_isGitHubAvailable_returnsFalse() async {
        let fetcher = DefaultOnlyFetcher()
        let result = await fetcher.isGitHubAvailable(repositoryPath: "/tmp/repo")
        #expect(false == result)
    }
}
