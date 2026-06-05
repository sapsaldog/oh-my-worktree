import Foundation
import Testing

@testable import OhMyWorktree

// MARK: - Keyed mock executor

private enum DetailTestError: Error { case boom }

private final class MockDetailGitExecutor: GitCommandExecuting, @unchecked Sendable {
    var responder: @Sendable ([String]) -> CommandResult
    var errorToThrow: Error?

    init(responder: @escaping @Sendable ([String]) -> CommandResult = { _ in
        CommandResult(stdout: "", stderr: "", exitCode: 0)
    }) {
        self.responder = responder
    }

    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        if let errorToThrow { throw errorToThrow }
        return responder(arguments)
    }
}

private func makeManager(_ responder: @escaping @Sendable ([String]) -> CommandResult) -> WorktreeManager {
    WorktreeManager(executor: MockDetailGitExecutor(responder: responder), fileManager: MockNoOpFileManager())
}

// MARK: - Model tests

@Suite
struct WorktreeDetailModelTests {

    @Test func diffStatIsEmpty() {
        #expect(DiffStat(added: 0, removed: 0, files: 0).isEmpty)
        #expect(!DiffStat(added: 1, removed: 2, files: 1).isEmpty)
    }

    @Test func commitIdIsHash() {
        #expect(Commit(hash: "abc1234", message: "m", author: "a", date: nil).id == "abc1234")
    }

    @Test func emptyDetailHasNoData() {
        #expect(WorktreeDetail.empty.aheadBehind == nil)
        #expect(WorktreeDetail.empty.diff.isEmpty)
        #expect(WorktreeDetail.empty.commits.isEmpty)
        #expect(WorktreeDetail.empty.copiedFiles.isEmpty)
    }
}

// MARK: - Pure parser tests

@Suite
struct WorktreeDetailParserTests {

    @Test func aheadBehindTabSeparated() {
        #expect(WorktreeManager.parseAheadBehind("2\t5\n") == AheadBehind(ahead: 5, behind: 2))
    }

    @Test func aheadBehindSpaceSeparated() {
        #expect(WorktreeManager.parseAheadBehind("1 2") == AheadBehind(ahead: 2, behind: 1))
    }

    @Test func aheadBehindInvalid() {
        #expect(WorktreeManager.parseAheadBehind("bad") == nil)
        #expect(WorktreeManager.parseAheadBehind("1\t2\t3") == nil)
        #expect(WorktreeManager.parseAheadBehind("x\ty") == nil)
    }

    @Test func diffStatSumsAndCountsBinary() {
        let stat = WorktreeManager.parseDiffStat("1\t2\tfile.swift\n-\t-\timage.png\n10\t3\tlib.swift\n")
        #expect(stat == DiffStat(added: 11, removed: 5, files: 3))
    }

    @Test func diffStatEmptyAndMalformed() {
        #expect(WorktreeManager.parseDiffStat("") == DiffStat(added: 0, removed: 0, files: 0))
        #expect(WorktreeManager.parseDiffStat("garbage line\n") == DiffStat(added: 0, removed: 0, files: 0))
    }

    @Test func commitsParseFields() {
        let out = "h1\u{1f}msg one\u{1f}alice\u{1f}1700000000\nh2\u{1f}msg two\u{1f}bob\u{1f}1700000100\n"
        let commits = WorktreeManager.parseCommits(out)
        #expect(commits.count == 2)
        #expect(commits[0].hash == "h1")
        #expect(commits[0].message == "msg one")
        #expect(commits[0].author == "alice")
        #expect(commits[0].date == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func commitsSkipMalformedAndBadDate() {
        let out = "only\u{1f}three\u{1f}fields\nh\u{1f}m\u{1f}a\u{1f}notanumber\n"
        let commits = WorktreeManager.parseCommits(out)
        #expect(commits.count == 1)
        #expect(commits[0].date == nil)
    }
}

// MARK: - Async query tests

@Suite
struct WorktreeDetailQueryTests {

    @Test func aheadBehindSuccess() async {
        let mgr = makeManager { args in
            args.first == "rev-list"
                ? CommandResult(stdout: "3\t7\n", stderr: "", exitCode: 0)
                : CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        #expect(await mgr.aheadBehind(worktreePath: "/x", baseBranch: "main") == AheadBehind(ahead: 7, behind: 3))
    }

    @Test func aheadBehindFailureReturnsNil() async {
        let mgr = makeManager { _ in CommandResult(stdout: "", stderr: "bad revision", exitCode: 128) }
        #expect(await mgr.aheadBehind(worktreePath: "/x", baseBranch: "main") == nil)
    }

    @Test func aheadBehindThrowReturnsNil() async {
        let mock = MockDetailGitExecutor()
        mock.errorToThrow = DetailTestError.boom
        let mgr = WorktreeManager(executor: mock, fileManager: MockNoOpFileManager())
        #expect(await mgr.aheadBehind(worktreePath: "/x", baseBranch: "main") == nil)
    }

    @Test func defaultBranchFromOriginHead() async {
        let mgr = makeManager { _ in CommandResult(stdout: "origin/develop\n", stderr: "", exitCode: 0) }
        #expect(await mgr.defaultBranch(repositoryPath: "/x") == "develop")
    }

    @Test func defaultBranchNoSlash() async {
        let mgr = makeManager { _ in CommandResult(stdout: "trunk\n", stderr: "", exitCode: 0) }
        #expect(await mgr.defaultBranch(repositoryPath: "/x") == "trunk")
    }

    @Test func defaultBranchEmptyFallsBack() async {
        let mgr = makeManager { _ in CommandResult(stdout: "\n", stderr: "", exitCode: 0) }
        #expect(await mgr.defaultBranch(repositoryPath: "/x") == "main")
    }

    @Test func defaultBranchTrailingSlashFallsBack() async {
        let mgr = makeManager { _ in CommandResult(stdout: "origin/\n", stderr: "", exitCode: 0) }
        #expect(await mgr.defaultBranch(repositoryPath: "/x") == "main")
    }

    @Test func defaultBranchFailureFallsBack() async {
        let mgr = makeManager { _ in CommandResult(stdout: "", stderr: "err", exitCode: 1) }
        #expect(await mgr.defaultBranch(repositoryPath: "/x") == "main")
    }

    @Test func diffStatSuccess() async {
        let mgr = makeManager { args in
            switch args.first {
            case "merge-base": return CommandResult(stdout: "base123\n", stderr: "", exitCode: 0)
            case "diff": return CommandResult(stdout: "1\t2\ta\n-\t-\tb\n", stderr: "", exitCode: 0)
            default: return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
        }
        #expect(await mgr.diffStat(worktreePath: "/x", baseBranch: "main") == DiffStat(added: 1, removed: 2, files: 2))
    }

    @Test func diffStatMergeBaseEmptyUsesBaseBranch() async {
        let mgr = makeManager { args in
            switch args.first {
            case "merge-base": return CommandResult(stdout: "   \n", stderr: "", exitCode: 0)   // empty after trim
            case "diff": return CommandResult(stdout: "5\t0\tx\n", stderr: "", exitCode: 0)
            default: return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
        }
        #expect(await mgr.diffStat(worktreePath: "/x", baseBranch: "main") == DiffStat(added: 5, removed: 0, files: 1))
    }

    @Test func diffStatEmptyBaseReturnsEmpty() async {
        let mgr = makeManager { args in
            args.first == "merge-base"
                ? CommandResult(stdout: "", stderr: "x", exitCode: 1)   // fail → returns baseBranch ("")
                : CommandResult(stdout: "9\t9\tz\n", stderr: "", exitCode: 0)
        }
        #expect(await mgr.diffStat(worktreePath: "/x", baseBranch: "") == DiffStat(added: 0, removed: 0, files: 0))
    }

    @Test func diffStatDiffFailsReturnsEmpty() async {
        let mgr = makeManager { args in
            args.first == "merge-base"
                ? CommandResult(stdout: "base\n", stderr: "", exitCode: 0)
                : CommandResult(stdout: "", stderr: "boom", exitCode: 1)
        }
        #expect(await mgr.diffStat(worktreePath: "/x", baseBranch: "main") == DiffStat(added: 0, removed: 0, files: 0))
    }

    @Test func recentCommitsSuccess() async {
        let mgr = makeManager { args in
            args.first == "log"
                ? CommandResult(stdout: "h1\u{1f}m\u{1f}a\u{1f}1700000000\n", stderr: "", exitCode: 0)
                : CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        let commits = await mgr.recentCommits(worktreePath: "/x")
        #expect(commits.count == 1)
        #expect(commits.first?.hash == "h1")
    }

    @Test func recentCommitsFailureReturnsEmpty() async {
        let mgr = makeManager { _ in CommandResult(stdout: "", stderr: "err", exitCode: 1) }
        #expect(await mgr.recentCommits(worktreePath: "/x").isEmpty)
    }

    @Test func worktreeDetailAggregates() async {
        let mgr = makeManager { args in
            switch args.first {
            case "symbolic-ref": return CommandResult(stdout: "origin/main\n", stderr: "", exitCode: 0)
            case "rev-list": return CommandResult(stdout: "1\t4\n", stderr: "", exitCode: 0)
            case "merge-base": return CommandResult(stdout: "base\n", stderr: "", exitCode: 0)
            case "diff": return CommandResult(stdout: "2\t1\tf\n", stderr: "", exitCode: 0)
            case "log": return CommandResult(stdout: "h\u{1f}m\u{1f}a\u{1f}1700000000\n", stderr: "", exitCode: 0)
            default: return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
        }
        let detail = await mgr.worktreeDetail(worktreePath: "/x", repositoryPath: "/repo")
        #expect(detail.aheadBehind == AheadBehind(ahead: 4, behind: 1))
        #expect(detail.diff == DiffStat(added: 2, removed: 1, files: 1))
        #expect(detail.commits.count == 1)
    }
}
