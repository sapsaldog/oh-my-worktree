import Foundation
import Testing

@testable import OhMyWorktree

// MARK: - gh CLI Discovery (findGhCli / resolveFromPath)
//
// `.serialized`: these tests mutate the process-global `PATH` (and spawn
// `/usr/bin/which`), so they must not run concurrently with one another —
// parallel execution would let one test's PATH leak into another. No other
// suite touches PATH, so serializing this suite is sufficient.
@Suite(.serialized) struct PullRequestServiceDiscoveryTests {

    /// Builds a temp directory containing an executable named `gh`. Returns the
    /// directory URL and the full path to the fake executable. Caller cleans up.
    private func makeFakeGhDir() throws -> (dir: URL, ghPath: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omw-gh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ghURL = dir.appendingPathComponent("gh")
        try "#!/bin/sh\nexit 0\n".write(to: ghURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: ghURL.path
        )
        return (dir, ghURL.path)
    }

    /// Sets `PATH` to `dir` for the duration of `body`, restoring it afterwards.
    private func withPath(_ dir: String, _ body: () throws -> Void) rethrows {
        let savedPath = ProcessInfo.processInfo.environment["PATH"]
        setenv("PATH", dir, 1)
        defer {
            if let savedPath { setenv("PATH", savedPath, 1) } else { unsetenv("PATH") }
        }
        try body()
    }

    @Test func resolveFromPath_findsExecutableOnPath() throws {
        let (dir, expectedPath) = try makeFakeGhDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try withPath(dir.path) {
            let resolved = PullRequestService.resolveFromPath("gh")

            // /usr/bin/which may canonicalize symlinks (e.g. /private/var -> /var),
            // so compare on the resolved filesystem identity rather than raw string.
            let resolvedReal = resolved.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
            let expectedReal = URL(fileURLWithPath: expectedPath).resolvingSymlinksInPath().path
            #expect(resolvedReal == expectedReal)
        }
    }

    @Test func resolveFromPath_returnsNilWhenNotFound() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omw-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try withPath(dir.path) {
            let resolved = PullRequestService.resolveFromPath("definitely-not-a-real-binary-\(UUID().uuidString)")
            #expect(resolved == nil)
        }
    }

    @Test func findGhCli_returnsCommonPathWhenPresent() throws {
        let (dir, ghPath) = try makeFakeGhDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // The fake gh path is supplied as the first common path, so the PATH
        // fallback is never consulted.
        let found = PullRequestService.findGhCli(commonPaths: [ghPath, "/nonexistent/gh"])

        #expect(found == ghPath)
    }

    @Test func findGhCli_fallsBackToPathWhenCommonPathsMissing() throws {
        let (dir, expectedPath) = try makeFakeGhDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try withPath(dir.path) {
            // No common path exists, so findGhCli must fall through to resolveFromPath.
            let found = PullRequestService.findGhCli(commonPaths: ["/nonexistent/a/gh", "/nonexistent/b/gh"])

            let foundReal = found.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
            let expectedReal = URL(fileURLWithPath: expectedPath).resolvingSymlinksInPath().path
            #expect(foundReal == expectedReal)
        }
    }

    @Test func findGhCli_returnsNilWhenNeitherCommonPathNorPathHasGh() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omw-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try withPath(dir.path) {
            let found = PullRequestService.findGhCli(commonPaths: ["/nonexistent/a/gh"])
            #expect(found == nil)
        }
    }

    // Drives the `init` default-argument call site `Self.findGhCli()` (ghCliPath nil).
    @Test func init_withNilGhCliPath_resolvesViaFindGhCli() async {
        let mock = MockGitCommandExecutor()
        mock.stubGitConfig(remoteURL: "git@gitlab.com:user/repo.git")
        // ghCliPath omitted -> init calls Self.findGhCli() with default common paths.
        let sut = PullRequestService(gitExecutor: mock)

        // Non-GitHub remote -> returns empty regardless of whether gh was found,
        // so this stays deterministic across machines.
        let result = await sut.fetchPullRequests(repositoryPath: "/tmp/repo")

        #expect(result.isEmpty)
    }

    // The final guard rejects a `which` result whose printed path is not an
    // executable file. A fake `which` that prints a plain (non-executable) file
    // path satisfies terminationStatus == 0 but fails `isExecutableFile`,
    // hitting that else branch.
    @Test func resolveFromPath_whenResultIsNotExecutable_returnsNil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omw-fakewhich-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // A non-executable regular file: isExecutableFile(atPath:) returns false
        // for it (unlike a directory, which is "executable"/searchable).
        let plainFile = dir.appendingPathComponent("not-executable.txt")
        try "data".write(to: plainFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plainFile.path)

        // A stand-in `which` that always succeeds and prints the plain file path.
        let fakeWhich = dir.appendingPathComponent("which")
        try "#!/bin/sh\necho '\(plainFile.path)'\nexit 0\n".write(to: fakeWhich, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWhich.path)

        let resolved = PullRequestService.resolveFromPath("gh", whichPath: fakeWhich.path)

        #expect(resolved == nil)
    }

    // A fake `which` that succeeds but prints an empty line exercises the
    // `!path.isEmpty` portion of the final guard.
    @Test func resolveFromPath_whenResultIsEmpty_returnsNil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omw-emptywhich-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fakeWhich = dir.appendingPathComponent("which")
        try "#!/bin/sh\necho ''\nexit 0\n".write(to: fakeWhich, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWhich.path)

        let resolved = PullRequestService.resolveFromPath("gh", whichPath: fakeWhich.path)

        #expect(resolved == nil)
    }

    // Spawning a non-existent `which` makes `process.run()` throw, covering the
    // catch branch of resolveFromPath.
    @Test func resolveFromPath_whenSpawnThrows_returnsNil() {
        let missing = "/nonexistent/which-\(UUID().uuidString)"

        let resolved = PullRequestService.resolveFromPath("gh", whichPath: missing)

        #expect(resolved == nil)
    }
}
