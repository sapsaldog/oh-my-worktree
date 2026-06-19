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

    @Test func compareSurfacesMissingFileAsRemoved() {
        // Exists in main, never copied into the worktree: it must surface as
        // `.missing` showing main's content as removed lines — not be skipped.
        write("ghost.env", in: repoDir, "A=1\nB=2")
        let files = sut.compare(relativePaths: ["ghost.env"],
                                worktreePath: worktreeDir, repositoryPath: repoDir)
        #expect(files.count == 1)
        let file = files[0]
        #expect(file.status == .missing)
        #expect(file.isBinary == false)
        #expect(file.added == 0)
        #expect(file.removed == 2)
        #expect(file.mainContent == "A=1\nB=2")
        #expect(file.worktreeContent == nil)
        #expect(file.lines.allSatisfy { $0.kind == .del })
        #expect(file.status.isChanged)
    }

    @Test func compareSurfacesMissingBinaryFile() {
        write("blob.bin", in: repoDir, Data([0xFF, 0x00, 0xFE]))   // non-UTF-8, main only
        let files = sut.compare(relativePaths: ["blob.bin"],
                                worktreePath: worktreeDir, repositoryPath: repoDir)
        #expect(files.first?.status == .missing)
        #expect(files.first?.isBinary == true)
        #expect(files.first?.lines.isEmpty == true)
    }

    @Test func compareSkipsPathAbsentOnBothSides() {
        // Defensive: a candidate that exists in neither side is dropped entirely.
        let files = sut.compare(relativePaths: ["nowhere.env"],
                                worktreePath: worktreeDir, repositoryPath: repoDir)
        #expect(files.isEmpty)
    }

    @Test func classifyBothNilIsMissingAndEmpty() {
        let file = CopiedFile.classify(path: "x.env", mainData: nil, worktreeData: nil)
        #expect(file.status == .missing)
        #expect(file.isBinary == false)
        #expect(file.lines.isEmpty)
        #expect(file.mainContent == nil)
        #expect(file.worktreeContent == nil)
    }

    @Test func compareSortsModifiedMissingNewIdentical() {
        write("m.env", in: repoDir, "1"); write("m.env", in: worktreeDir, "2")        // modified
        write("gone.env", in: repoDir, "x")                                           // missing
        write("fresh.env", in: worktreeDir, "y")                                      // new
        write("same.env", in: repoDir, "z"); write("same.env", in: worktreeDir, "z")  // identical

        let files = sut.compare(relativePaths: ["same.env", "fresh.env", "gone.env", "m.env"],
                                worktreePath: worktreeDir, repositoryPath: repoDir)
        // sortRank: modified(0) → missing(1) → new(2) → identical(3)
        #expect(files.map(\.status) == [.modified, .missing, .new, .identical])
    }

    @Test func compareDetectsBinaryModified() {
        write("a.bin", in: repoDir, Data([0xFF, 0x00]))
        write("a.bin", in: worktreeDir, Data([0xFF, 0x01]))
        let files = sut.compare(relativePaths: ["a.bin"],
                                worktreePath: worktreeDir, repositoryPath: repoDir)
        #expect(files.first?.status == .modified)
        #expect(files.first?.isBinary == true)
    }
}
