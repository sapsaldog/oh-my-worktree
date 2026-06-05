import Foundation
import Testing

@testable import OhMyWorktree

@Suite
final class WorktreeFileCopierTests {

    private let repoDir: String
    private let worktreeDir: String
    private let fm = FileManager.default
    private let sut = WorktreeFileCopier()

    init() {
        let base = NSTemporaryDirectory() + "WorktreeFileCopierTests-\(UUID().uuidString)"
        repoDir = base + "/repo"
        worktreeDir = base + "/worktree"
        try! fm.createDirectory(atPath: repoDir, withIntermediateDirectories: true)
        try! fm.createDirectory(atPath: worktreeDir, withIntermediateDirectories: true)
    }

    deinit {
        let base = (repoDir as NSString).deletingLastPathComponent
        try? fm.removeItem(atPath: base)
    }

    private func createFile(_ relativePath: String, in dir: String? = nil, content: String = "test") {
        let root = dir ?? repoDir
        let fullPath = (root as NSString).appendingPathComponent(relativePath)
        let parentDir = (fullPath as NSString).deletingLastPathComponent
        try! fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        fm.createFile(atPath: fullPath, contents: content.data(using: .utf8))
    }

    private func createWorktreeInclude(_ content: String) {
        createFile(".worktreeinclude", content: content)
    }

    private func fileExists(_ relativePath: String, in dir: String? = nil) -> Bool {
        let root = dir ?? worktreeDir
        return fm.fileExists(atPath: (root as NSString).appendingPathComponent(relativePath))
    }

    @Test func legacyFallback_copiesEnvFiles() {
        createFile(".env")
        createFile(".env.local")
        createFile(".env.development")
        createFile("README.md")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(Set(result.copiedFiles) == [".env", ".env.local", ".env.development"])
        #expect(result.errors.isEmpty)
        #expect(fileExists(".env"))
        #expect(fileExists(".env.local"))
        #expect(false == fileExists("README.md"))
    }

    @Test func legacyFallback_copiesNestedEnvFiles() {
        createFile(".env")
        createFile("apps/web/.env.local")
        createFile("packages/api/.env.development")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles.count == 3)
        #expect(fileExists("apps/web/.env.local"))
        #expect(fileExists("packages/api/.env.development"))
    }

    // MARK: - includedFiles (detail-pane "Copied files" listing)

    @Test func includedFiles_listsEnvFilesWhenNoIncludeFile() {
        createFile(".env", in: worktreeDir)
        createFile(".env.local", in: worktreeDir)
        createFile("README.md", in: worktreeDir)

        #expect(Set(sut.includedFiles(in: worktreeDir)) == [".env", ".env.local"])
    }

    @Test func includedFiles_usesWorktreeIncludePatterns() {
        createFile(".worktreeinclude", in: worktreeDir, content: "*.pem\nconfig/local/*")
        createFile("certs/dev.pem", in: worktreeDir)
        createFile("config/local/db.yml", in: worktreeDir)
        createFile("src/main.swift", in: worktreeDir)

        let files = sut.includedFiles(in: worktreeDir)
        #expect(files.contains("certs/dev.pem"))
        #expect(files.contains("config/local/db.yml"))
        #expect(false == files.contains("src/main.swift"))
    }

    @Test func legacyFallback_skipsExcludedDirs() {
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

        #expect(result.copiedFiles == [".env"])
    }

    @Test func legacyFallback_noEnvFiles_returnsEmpty() {
        createFile("README.md")
        createFile("src/main.swift")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles.isEmpty)
        #expect(result.errors.isEmpty)
    }

    @Test func legacyFallback_skipsExistingFiles() {
        createFile(".env", content: "SOURCE")
        createFile(".env", in: worktreeDir, content: "EXISTING")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles.isEmpty)
        let destPath = (worktreeDir as NSString).appendingPathComponent(".env")
        let content = try! String(contentsOfFile: destPath)
        #expect(content == "EXISTING")
    }

    @Test func worktreeInclude_simpleFilenamePattern() {
        createWorktreeInclude(".env*")
        createFile(".env")
        createFile(".env.local")
        createFile("README.md")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(Set(result.copiedFiles) == [".env", ".env.local"])
        #expect(false == fileExists("README.md"))
    }

    @Test func worktreeInclude_filenamePatternMatchesNestedFiles() {
        createWorktreeInclude(".env*")
        createFile(".env")
        createFile("apps/web/.env.local")
        createFile("deep/nested/path/.env.production")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles.count == 3)
        #expect(fileExists("apps/web/.env.local"))
        #expect(fileExists("deep/nested/path/.env.production"))
    }

    @Test func worktreeInclude_exactPathPattern() {
        createWorktreeInclude("config/local.yml")
        createFile("config/local.yml")
        createFile("config/production.yml")
        createFile("other/config/local.yml")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles == ["config/local.yml"])
    }

    @Test func worktreeInclude_doubleStarPattern() {
        createWorktreeInclude("**/*.local.json")
        createFile("settings.local.json")
        createFile("config/db.local.json")
        createFile("deep/nested/app.local.json")
        createFile("config/db.production.json")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(Set(result.copiedFiles) == [
            "config/db.local.json",
            "deep/nested/app.local.json",
            "settings.local.json"
        ])
        #expect(false == fileExists("config/db.production.json"))
    }

    @Test func worktreeInclude_vscodeSettingsPattern() {
        createWorktreeInclude(".vscode/settings.json")
        createFile(".vscode/settings.json")
        createFile(".vscode/extensions.json")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles == [".vscode/settings.json"])
    }

    @Test func worktreeInclude_multiplePatterns() {
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

        #expect(Set(result.copiedFiles) == [
            ".env",
            ".env.local",
            ".vscode/settings.json",
            "config/local.yml",
            "src/db.local.json"
        ])
    }

    @Test func worktreeInclude_ignoresCommentsAndBlankLines() {
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

        #expect(Set(result.copiedFiles) == [".env", "config/local.yml"])
    }

    @Test func worktreeInclude_emptyFile_copiesNothing() {
        createWorktreeInclude("")
        createFile(".env")
        createFile("config/local.yml")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles.isEmpty)
        #expect(result.errors.isEmpty)
    }

    @Test func worktreeInclude_onlyCommentsAndBlanks_copiesNothing() {
        createWorktreeInclude("""
        # Only comments
        # No actual patterns

        """)
        createFile(".env")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles.isEmpty)
    }

    @Test func worktreeInclude_skipsExcludedDirs() {
        createWorktreeInclude("*.json")
        createFile("config.json")
        createFile("node_modules/package.json")
        createFile(".git/config.json")
        createFile("dist/bundle.json")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles == ["config.json"])
    }

    @Test func worktreeInclude_skipsExistingFiles() {
        createWorktreeInclude(".env*")
        createFile(".env", content: "SOURCE_VALUE")
        createFile(".env.local", content: "LOCAL_VALUE")
        createFile(".env", in: worktreeDir, content: "KEEP_THIS")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles == [".env.local"])
        let destContent = try! String(contentsOfFile: (worktreeDir as NSString).appendingPathComponent(".env"))
        #expect(destContent == "KEEP_THIS")
    }

    @Test func worktreeInclude_pathWithWildcard() {
        createWorktreeInclude("config/*.yml")
        createFile("config/local.yml")
        createFile("config/production.yml")
        createFile("config/nested/deep.yml")
        createFile("other/local.yml")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(Set(result.copiedFiles) == ["config/local.yml", "config/production.yml"])
    }

    @Test func worktreeInclude_doubleStarWithSubdir() {
        createWorktreeInclude("**/config/*.yml")
        createFile("config/local.yml")
        createFile("apps/web/config/local.yml")
        createFile("packages/api/config/db.yml")
        createFile("standalone.yml")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(Set(result.copiedFiles) == [
            "apps/web/config/local.yml",
            "config/local.yml",
            "packages/api/config/db.yml"
        ])
    }

    @Test func emptyRepository_returnsEmpty() {
        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles.isEmpty)
        #expect(result.errors.isEmpty)
    }

    @Test func nonExistentRepoPath_returnsEmpty() {
        let result = sut.copyFiles(from: "/nonexistent/path", to: worktreeDir)

        #expect(result.copiedFiles.isEmpty)
        #expect(result.errors.isEmpty)
    }

    @Test func worktreeInclude_whitespaceOnlyLines() {
        createWorktreeInclude("   \n.env*\n   \n")
        createFile(".env")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles == [".env"])
    }

    @Test func worktreeInclude_createsIntermediateDirectories() {
        createWorktreeInclude("**/*.yml")
        createFile("a/b/c/d/config.yml")

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles == ["a/b/c/d/config.yml"])
        #expect(fileExists("a/b/c/d/config.yml"))
    }

    @Test func copyFailure_recordsError() throws {
        createWorktreeInclude(".env*")
        let sourcePath = (repoDir as NSString).appendingPathComponent(".env")
        createFile(".env", content: "SECRET")
        // Make the source unreadable so copyItem throws while the file is still
        // enumerated and passes fileExists — exercising the catch/error path.
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sourcePath)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: sourcePath) }

        let result = sut.copyFiles(from: repoDir, to: worktreeDir)

        #expect(result.copiedFiles.isEmpty)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].hasPrefix(".env:"))
        #expect(false == fileExists(".env"))
    }

    @Test func worktreeInclude_unenumerableDirectory_returnsEmpty() {
        // When .worktreeinclude yields patterns but the directory cannot be
        // enumerated, findMatchingFiles returns []. FileManager.enumerator(atPath:)
        // returns nil for an empty path, while contents(atPath:) on a relative
        // ".worktreeinclude" resolves against the current working directory.
        createWorktreeInclude(".env*")
        createFile(".env")

        let savedCWD = fm.currentDirectoryPath
        defer { _ = fm.changeCurrentDirectoryPath(savedCWD) }
        #expect(fm.changeCurrentDirectoryPath(repoDir))

        let result = sut.copyFiles(from: "", to: worktreeDir)

        #expect(result.copiedFiles.isEmpty)
        #expect(result.errors.isEmpty)
    }
}
