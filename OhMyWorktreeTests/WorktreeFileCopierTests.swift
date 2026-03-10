import XCTest

@testable import OhMyWorktree

final class WorktreeFileCopierTests: XCTestCase {

    private var repoDir: String!
    private var worktreeDir: String!
    private let fm = FileManager.default
    private let sut = WorktreeFileCopier()

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        let base = NSTemporaryDirectory() + "WorktreeFileCopierTests-\(UUID().uuidString)"
        repoDir = base + "/repo"
        worktreeDir = base + "/worktree"
        try! fm.createDirectory(atPath: repoDir, withIntermediateDirectories: true)
        try! fm.createDirectory(atPath: worktreeDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        let base = (repoDir as NSString).deletingLastPathComponent
        try? fm.removeItem(atPath: base)
        super.tearDown()
    }

    // MARK: - Helpers

    private func createFile(_ relativePath: String, in dir: String? = nil, content: String = "test") {
        let root = dir ?? repoDir!
        let fullPath = (root as NSString).appendingPathComponent(relativePath)
        let parentDir = (fullPath as NSString).deletingLastPathComponent
        try! fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        fm.createFile(atPath: fullPath, contents: content.data(using: .utf8))
    }

    private func createWorktreeInclude(_ content: String) {
        createFile(".worktreeinclude", content: content)
    }

    private func fileExists(_ relativePath: String, in dir: String? = nil) -> Bool {
        let root = dir ?? worktreeDir!
        return fm.fileExists(atPath: (root as NSString).appendingPathComponent(relativePath))
    }

    // MARK: - Legacy Fallback (no .worktreeinclude)

    func testLegacyFallback_copiesEnvFiles() {
        createFile(".env")
        createFile(".env.local")
        createFile(".env.development")
        createFile("README.md")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(Set(result.copiedFiles), [".env", ".env.local", ".env.development"])
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(fileExists(".env"))
        XCTAssertTrue(fileExists(".env.local"))
        XCTAssertFalse(fileExists("README.md"))
    }

    func testLegacyFallback_copiesNestedEnvFiles() {
        createFile(".env")
        createFile("apps/web/.env.local")
        createFile("packages/api/.env.development")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(result.copiedFiles.count, 3)
        XCTAssertTrue(fileExists("apps/web/.env.local"))
        XCTAssertTrue(fileExists("packages/api/.env.development"))
    }

    func testLegacyFallback_skipsExcludedDirs() {
        createFile(".env")
        createFile("node_modules/.env")
        createFile(".git/.env")
        createFile("dist/.env.local")
        createFile("build/.env.test")
        createFile(".next/.env")
        createFile(".nuxt/.env")
        createFile(".output/.env")
        createFile(".omc/.env")
        createFile(".claude/.env")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(result.copiedFiles, [".env"])
    }

    func testLegacyFallback_noEnvFiles_returnsEmpty() {
        createFile("README.md")
        createFile("src/main.swift")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertTrue(result.copiedFiles.isEmpty)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testLegacyFallback_skipsExistingFiles() {
        createFile(".env", content: "SOURCE")
        createFile(".env", in: worktreeDir, content: "EXISTING")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertTrue(result.copiedFiles.isEmpty)
        // Verify existing file was NOT overwritten
        let destPath = (worktreeDir as NSString).appendingPathComponent(".env")
        let content = try! String(contentsOfFile: destPath)
        XCTAssertEqual(content, "EXISTING")
    }

    // MARK: - .worktreeinclude — Basic Patterns

    func testWorktreeInclude_simpleFilenamePattern() {
        createWorktreeInclude(".env*")
        createFile(".env")
        createFile(".env.local")
        createFile("README.md")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(Set(result.copiedFiles), [".env", ".env.local"])
        XCTAssertFalse(fileExists("README.md"))
    }

    func testWorktreeInclude_filenamePatternMatchesNestedFiles() {
        createWorktreeInclude(".env*")
        createFile(".env")
        createFile("apps/web/.env.local")
        createFile("deep/nested/path/.env.production")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(result.copiedFiles.count, 3)
        XCTAssertTrue(fileExists("apps/web/.env.local"))
        XCTAssertTrue(fileExists("deep/nested/path/.env.production"))
    }

    func testWorktreeInclude_exactPathPattern() {
        createWorktreeInclude("config/local.yml")
        createFile("config/local.yml")
        createFile("config/production.yml")
        createFile("other/config/local.yml")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(result.copiedFiles, ["config/local.yml"])
    }

    func testWorktreeInclude_doubleStarPattern() {
        createWorktreeInclude("**/*.local.json")
        createFile("settings.local.json")
        createFile("config/db.local.json")
        createFile("deep/nested/app.local.json")
        createFile("config/db.production.json")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(Set(result.copiedFiles), [
            "config/db.local.json",
            "deep/nested/app.local.json",
            "settings.local.json"
        ])
        XCTAssertFalse(fileExists("config/db.production.json"))
    }

    func testWorktreeInclude_vscodeSettingsPattern() {
        createWorktreeInclude(".vscode/settings.json")
        createFile(".vscode/settings.json")
        createFile(".vscode/extensions.json")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(result.copiedFiles, [".vscode/settings.json"])
    }

    // MARK: - .worktreeinclude — Multiple Patterns

    func testWorktreeInclude_multiplePatterns() {
        createWorktreeInclude("""
        .env*
        config/local.yml
        **/*.local.json
        .vscode/settings.json
        """)
        createFile(".env")
        createFile(".env.local")
        createFile("config/local.yml")
        createFile("config/production.yml")
        createFile("src/db.local.json")
        createFile(".vscode/settings.json")
        createFile(".vscode/extensions.json")
        createFile("README.md")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(Set(result.copiedFiles), [
            ".env",
            ".env.local",
            ".vscode/settings.json",
            "config/local.yml",
            "src/db.local.json"
        ])
    }

    // MARK: - .worktreeinclude — Comments & Blank Lines

    func testWorktreeInclude_ignoresCommentsAndBlankLines() {
        createWorktreeInclude("""
        # This is a comment
        .env*

        # Another comment

        config/local.yml
        """)
        createFile(".env")
        createFile("config/local.yml")
        createFile("README.md")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(Set(result.copiedFiles), [".env", "config/local.yml"])
    }

    // MARK: - .worktreeinclude — Empty File

    func testWorktreeInclude_emptyFile_copiesNothing() {
        createWorktreeInclude("")
        createFile(".env")
        createFile("config/local.yml")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertTrue(result.copiedFiles.isEmpty)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testWorktreeInclude_onlyCommentsAndBlanks_copiesNothing() {
        createWorktreeInclude("""
        # Only comments
        # No actual patterns

        """)
        createFile(".env")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertTrue(result.copiedFiles.isEmpty)
    }

    // MARK: - .worktreeinclude — Excluded Directories

    func testWorktreeInclude_skipsExcludedDirs() {
        createWorktreeInclude("*.json")
        createFile("config.json")
        createFile("node_modules/package.json")
        createFile(".git/config.json")
        createFile("dist/bundle.json")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(result.copiedFiles, ["config.json"])
    }

    // MARK: - .worktreeinclude — Skip Existing

    func testWorktreeInclude_skipsExistingFiles() {
        createWorktreeInclude(".env*")
        createFile(".env", content: "SOURCE_VALUE")
        createFile(".env.local", content: "LOCAL_VALUE")
        createFile(".env", in: worktreeDir, content: "KEEP_THIS")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(result.copiedFiles, [".env.local"])
        let destContent = try! String(contentsOfFile: (worktreeDir as NSString).appendingPathComponent(".env"))
        XCTAssertEqual(destContent, "KEEP_THIS")
    }

    // MARK: - .worktreeinclude — Wildcard Path Patterns

    func testWorktreeInclude_pathWithWildcard() {
        createWorktreeInclude("config/*.yml")
        createFile("config/local.yml")
        createFile("config/production.yml")
        createFile("config/nested/deep.yml")
        createFile("other/local.yml")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(Set(result.copiedFiles), ["config/local.yml", "config/production.yml"])
    }

    func testWorktreeInclude_doubleStarWithSubdir() {
        createWorktreeInclude("**/config/*.yml")
        createFile("config/local.yml")
        createFile("apps/web/config/local.yml")
        createFile("packages/api/config/db.yml")
        createFile("standalone.yml")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(Set(result.copiedFiles), [
            "apps/web/config/local.yml",
            "config/local.yml",
            "packages/api/config/db.yml"
        ])
    }

    // MARK: - Edge Cases

    func testEmptyRepository_returnsEmpty() {
        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertTrue(result.copiedFiles.isEmpty)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testNonExistentRepoPath_returnsEmpty() {
        let result = sut.copyFiles(from: "/nonexistent/path", to: worktreeDir)

        XCTAssertTrue(result.copiedFiles.isEmpty)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testWorktreeInclude_whitespaceOnlyLines() {
        createWorktreeInclude("   \n.env*\n   \n")
        createFile(".env")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(result.copiedFiles, [".env"])
    }

    func testWorktreeInclude_createsIntermediateDirectories() {
        createWorktreeInclude("**/*.yml")
        createFile("a/b/c/d/config.yml")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        XCTAssertEqual(result.copiedFiles, ["a/b/c/d/config.yml"])
        XCTAssertTrue(fileExists("a/b/c/d/config.yml"))
    }
}
