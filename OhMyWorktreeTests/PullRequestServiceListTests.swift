import Foundation
import Testing

@testable import OhMyWorktree

// Tests for `PullRequestService.fetchPullRequestList` (FR-031) — the rich PR
// list variant. Uses the shared MockGitCommandExecutor (see MockPRGitExecutor).
@Suite struct PullRequestServiceListTests {

    private let ghPath = "/usr/local/bin/gh"

    @Test func fetchPullRequestList_withValidJSON_parsesAllFields() async throws {
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
        let result = try #require(rawResult)

        #expect(result.count == 1)
        let pr = result[0]
        #expect(pr.number == 42)
        #expect(pr.branch == "feature/dark-mode")
        #expect(pr.title == "Add dark mode support")
        #expect(pr.author == "alice")
        #expect(pr.state == .open)
        #expect(false == pr.isDraft)
        #expect(pr.updatedAt != nil)
    }

    @Test func fetchPullRequestList_withDraftPR_setsDraftFlag() async throws {
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
        let result = try #require(rawResult)

        #expect(result.count == 1)
        #expect(result[0].isDraft)
    }

    @Test func fetchPullRequestList_withMissingAuthor_usesEmptyString() async throws {
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
        let result = try #require(rawResult)

        #expect(result.count == 1)
        #expect(result[0].author == "")
    }

    @Test func fetchPullRequestList_preservesOrder() async throws {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: """
        [
            {"number": 10, "url": "https://github.com/user/repo/pull/10",
             "headRefName": "a", "state": "OPEN", "title": "A",
             "author": {"login": "a"}, "updatedAt": null, "isDraft": false},
            {"number": 5, "url": "https://github.com/user/repo/pull/5",
             "headRefName": "b", "state": "OPEN", "title": "B",
             "author": {"login": "b"}, "updatedAt": null, "isDraft": false}
        ]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let rawResult = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")
        let result = try #require(rawResult)

        #expect(result.count == 2)
        #expect(result[0].number == 10)
        #expect(result[1].number == 5)
    }

    @Test func fetchPullRequestList_withNonGitHubRemote_returnsNil() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@gitlab.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")

        #expect(result == nil)
    }

    @Test func fetchPullRequestList_withNoGhCli_returnsNil() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: "/nonexistent/gh")

        let result = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")

        #expect(result == nil)
    }

    @Test func fetchPullRequestList_withCommandFailure_returnsNil() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFullFailure()
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")

        #expect(result == nil)
    }

    @Test func fetchPullRequestList_withInvalidJSON_returnsNil() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: "not json")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")

        #expect(result == nil)
    }

    @Test func fetchPullRequestList_withEmptyArray_returnsEmptyArray() async throws {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: "[]")
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let rawResult = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")
        let result = try #require(rawResult)

        #expect(result.isEmpty)
    }

    // Exercises the `URL(string:)` guard returning nil (compactMap drops the entry)
    // and the `state` flatMap + `updatedAt` fractional-seconds fallback path.
    @Test func fetchPullRequestList_withInvalidURL_dropsEntryAndParsesFallbackDate() async throws {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: """
        [
            {"number": 1, "url": "", "headRefName": "bad-url", "state": "OPEN",
             "title": "Dropped", "author": {"login": "x"}, "updatedAt": null, "isDraft": false},
            {"number": 2, "url": "https://github.com/user/repo/pull/2", "headRefName": "good",
             "state": "MERGED", "title": "Kept", "author": {"login": "y"},
             "updatedAt": "2024-01-15T10:30:00Z", "isDraft": false}
        ]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let rawResult = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")
        let result = try #require(rawResult)

        #expect(result.count == 1)
        #expect(result[0].number == 2)
        #expect(result[0].state == .merged)
        #expect(result[0].updatedAt != nil)
    }

    @Test func fetchPullRequestList_withMissingState_defaultsToOpen() async throws {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: """
        [{"number": 3, "url": "https://github.com/user/repo/pull/3", "headRefName": "no-state",
          "title": "No state", "author": {"login": "z"}, "updatedAt": null, "isDraft": false}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let rawResult = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")
        let result = try #require(rawResult)

        #expect(result.count == 1)
        #expect(result[0].state == .open)
    }

    // `isDraft: null` exercises the `pr.isDraft ?? false` default branch.
    @Test func fetchPullRequestList_withNullIsDraft_defaultsToFalse() async throws {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: """
        [{"number": 4, "url": "https://github.com/user/repo/pull/4", "headRefName": "nd",
          "state": "OPEN", "title": "No draft flag", "author": {"login": "z"},
          "updatedAt": null, "isDraft": null}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let rawResult = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")
        let result = try #require(rawResult)

        #expect(result.count == 1)
        #expect(false == result[0].isDraft)
    }

    // A `updatedAt` value WITHOUT fractional seconds makes the fractional
    // formatter return nil, exercising the `?? isoFormatterWithoutFractional`
    // fallback in parsePullRequestList.
    @Test func fetchPullRequestList_withNonFractionalDate_usesFallbackFormatter() async throws {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.stubGhPrListFull(json: """
        [{"number": 8, "url": "https://github.com/user/repo/pull/8", "headRefName": "dated",
          "state": "OPEN", "title": "Dated", "author": {"login": "z"},
          "updatedAt": "2024-01-15T10:30:00Z", "isDraft": false}]
        """)
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let rawResult = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")
        let result = try #require(rawResult)

        #expect(result.count == 1)
        #expect(result[0].updatedAt != nil)
    }

    @Test func fetchPullRequestList_whenExecutorThrows_returnsNil() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        mock.results.append((
            command: ghPath,
            arguments: [
                "pr", "list", "--json",
                "number,url,headRefName,state,title,author,updatedAt,isDraft",
                "--state", "all", "--limit", "100"
            ],
            result: .failure(NSError(domain: "test", code: 1,
                                     userInfo: [NSLocalizedDescriptionKey: "boom"]))
        ))
        let sut = PullRequestService(gitExecutor: mock, ghCliPath: ghPath)

        let result = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")

        #expect(result == nil)
    }

    // Resolver returns nil -> resolvedGhCliPath nil -> the "gh not found" guard
    // branch of fetchPullRequestList runs (deterministic, no real gh).
    @Test func fetchPullRequestList_whenGhUnresolved_returnsNil() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@github.com:user/repo.git")
        let sut = PullRequestService(gitExecutor: mock, ghCliResolver: { nil })

        let result = await sut.fetchPullRequestList(repositoryPath: "/tmp/repo")

        #expect(result == nil)
    }
}
