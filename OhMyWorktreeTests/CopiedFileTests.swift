import Foundation
import Testing

@testable import OhMyWorktree

@Suite
struct CopiedFileTests {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    // MARK: status flags

    @Test func statusFlags() {
        #expect(CopiedFileStatus.identical.isChanged == false)
        #expect(CopiedFileStatus.modified.isChanged)
        #expect(CopiedFileStatus.new.isChanged)
        #expect(CopiedFileStatus.modified.sortRank < CopiedFileStatus.new.sortRank)
        #expect(CopiedFileStatus.new.sortRank < CopiedFileStatus.identical.sortRank)
    }

    // MARK: path split

    @Test func pathSplit() {
        #expect(CopiedPath.split("apps/web/.env") == (dir: "apps/web/", base: ".env"))
        #expect(CopiedPath.split(".env") == (dir: "", base: ".env"))
        #expect(CopiedPath.split("a/") == (dir: "a/", base: ""))
    }

    // MARK: classify — text

    @Test func classifyIdentical() {
        let f = CopiedFile.classify(path: ".env", mainData: data("A=1"), worktreeData: data("A=1"))
        #expect(f.status == .identical)
        #expect(f.isBinary == false)
        #expect(f.added == 0 && f.removed == 0)
        #expect(f.lines.isEmpty)
    }

    @Test func classifyModifiedCountsLines() {
        let f = CopiedFile.classify(path: ".env",
                                    mainData: data("A=1\nB=2"),
                                    worktreeData: data("A=1\nB=3\nC=4"))
        #expect(f.status == .modified)
        #expect(f.isBinary == false)
        #expect(f.added == 2)    // "B=3", "C=4"
        #expect(f.removed == 1)  // "B=2"
        #expect(f.lines.isEmpty == false)
        #expect(f.mainContent == "A=1\nB=2")
        #expect(f.worktreeContent == "A=1\nB=3\nC=4")
    }

    @Test func classifyNewIsAllAdds() {
        let f = CopiedFile.classify(path: "new.env", mainData: nil, worktreeData: data("X=1\nY=2"))
        #expect(f.status == .new)
        #expect(f.isBinary == false)
        #expect(f.added == 2 && f.removed == 0)
        #expect(f.lines.map(\.kind) == [.add, .add])
        #expect(f.mainContent == nil)
    }

    // MARK: classify — binary

    @Test func classifyBinaryIdentical() {
        let bytes = Data([0xFF, 0x00, 0xFE])
        let f = CopiedFile.classify(path: "a.bin", mainData: bytes, worktreeData: bytes)
        #expect(f.status == .identical)
        #expect(f.isBinary)
        #expect(f.lines.isEmpty)
    }

    @Test func classifyBinaryModified() {
        let f = CopiedFile.classify(path: "a.bin",
                                    mainData: Data([0xFF, 0x00]),
                                    worktreeData: Data([0xFF, 0x01]))
        #expect(f.status == .modified)
        #expect(f.isBinary)
        #expect(f.added == 0 && f.removed == 0)
        #expect(f.lines.isEmpty)
    }

    @Test func classifyNewBinary() {
        let f = CopiedFile.classify(path: "k.p12", mainData: nil, worktreeData: Data([0x00, 0xFF]))
        #expect(f.status == .new)
        #expect(f.isBinary)
        #expect(f.lines.isEmpty)
    }

    @Test func identifiableUsesPath() {
        let f = CopiedFile.classify(path: "x/.env", mainData: data("a"), worktreeData: data("a"))
        #expect(f.id == "x/.env")
    }
}
