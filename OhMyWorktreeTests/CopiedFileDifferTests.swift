import Foundation
import Testing

@testable import OhMyWorktree

@Suite
final class CopiedFileDifferTests {

    private let repoDir: String
    private let worktreeDir: String
    private let fm = FileManager.default
    private let sut = CopiedFileDiffer()

    init() {
        let base = NSTemporaryDirectory() + "CopiedFileDifferTests-\(UUID().uuidString)"
        repoDir = base + "/repo"
        worktreeDir = base + "/worktree"
        try! fm.createDirectory(atPath: repoDir, withIntermediateDirectories: true)
        try! fm.createDirectory(atPath: worktreeDir, withIntermediateDirectories: true)
    }

    deinit {
        let base = (repoDir as NSString).deletingLastPathComponent
        try? fm.removeItem(atPath: base)
    }

    private func write(_ rel: String, in dir: String, _ bytes: Data) {
        let full = (dir as NSString).appendingPathComponent(rel)
        try! fm.createDirectory(atPath: (full as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true)
        fm.createFile(atPath: full, contents: bytes)
    }

    private func write(_ rel: String, in dir: String, _ text: String) {
        write(rel, in: dir, Data(text.utf8))
    }

    private func read(_ rel: String, in dir: String) -> Data? {
        fm.contents(atPath: (dir as NSString).appendingPathComponent(rel))
    }

    // MARK: compare

    @Test func compareClassifiesAndSorts() {
        write("apps/a/.env", in: repoDir, "A=1")
        write("apps/a/.env", in: worktreeDir, "A=2")       // modified
        write("same.env", in: repoDir, "X=1")
        write("same.env", in: worktreeDir, "X=1")          // identical
        write("brand.env", in: worktreeDir, "N=1")         // new (only in worktree)

        let files = sut.compare(relativePaths: ["same.env", "apps/a/.env", "brand.env"],
                                worktreePath: worktreeDir, repositoryPath: repoDir)

        // sorted: modified(0) → new(1) → identical(2)
        #expect(files.map(\.path) == ["apps/a/.env", "brand.env", "same.env"])
        #expect(files.map(\.status) == [.modified, .new, .identical])
    }

    @Test func compareSkipsMissingWorktreeFile() {
        write("ghost.env", in: repoDir, "A=1")   // exists in main, not in worktree
        let files = sut.compare(relativePaths: ["ghost.env"],
                                worktreePath: worktreeDir, repositoryPath: repoDir)
        #expect(files.isEmpty)
    }

    @Test func compareDetectsBinaryModified() {
        write("a.bin", in: repoDir, Data([0xFF, 0x00]))
        write("a.bin", in: worktreeDir, Data([0xFF, 0x01]))
        let files = sut.compare(relativePaths: ["a.bin"],
                                worktreePath: worktreeDir, repositoryPath: repoDir)
        #expect(files.first?.status == .modified)
        #expect(files.first?.isBinary == true)
    }

    // MARK: applyToMain

    @Test func applyOverwritesExistingMainCopy() throws {
        write("apps/a/.env", in: repoDir, "A=1")
        write("apps/a/.env", in: worktreeDir, "A=2\nB=3")
        let file = sut.compare(relativePaths: ["apps/a/.env"],
                               worktreePath: worktreeDir, repositoryPath: repoDir)[0]

        try sut.applyToMain(file, worktreePath: worktreeDir, repositoryPath: repoDir)

        #expect(read("apps/a/.env", in: repoDir) == Data("A=2\nB=3".utf8))
        // re-comparing now reports identical
        let after = sut.compare(relativePaths: ["apps/a/.env"],
                                worktreePath: worktreeDir, repositoryPath: repoDir)[0]
        #expect(after.status == .identical)
    }

    @Test func applyCopiesNewFileCreatingDirs() throws {
        write("config/local/new.json", in: worktreeDir, "{}")
        let file = sut.compare(relativePaths: ["config/local/new.json"],
                               worktreePath: worktreeDir, repositoryPath: repoDir)[0]
        #expect(file.status == .new)

        try sut.applyToMain(file, worktreePath: worktreeDir, repositoryPath: repoDir)

        #expect(read("config/local/new.json", in: repoDir) == Data("{}".utf8))
    }

    @Test func applyThrowsWhenSourceMissing() {
        let phantom = CopiedFile(path: "gone.env", status: .new, isBinary: false,
                                 added: 0, removed: 0, mainContent: nil,
                                 worktreeContent: nil, lines: [])
        #expect(throws: (any Error).self) {
            try sut.applyToMain(phantom, worktreePath: worktreeDir, repositoryPath: repoDir)
        }
    }

    @Test func applyThrowsWhenDestDirBlockedByFile() {
        // A *file* named "blocker" in repo blocks creating dir "blocker/".
        write("blocker", in: repoDir, "x")
        write("blocker/x.env", in: worktreeDir, "A=1")
        let file = sut.compare(relativePaths: ["blocker/x.env"],
                               worktreePath: worktreeDir, repositoryPath: repoDir)[0]
        #expect(throws: (any Error).self) {
            try sut.applyToMain(file, worktreePath: worktreeDir, repositoryPath: repoDir)
        }
    }
}
