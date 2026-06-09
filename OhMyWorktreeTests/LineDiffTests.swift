import Testing

@testable import OhMyWorktree

@Suite
struct LineDiffTests {

    @Test func identicalIsAllContext() {
        let rows = LineDiff.compute("a\nb\nc", "a\nb\nc")
        #expect(rows.allSatisfy { $0.kind == .context })
        #expect(rows.map(\.text) == ["a", "b", "c"])
        #expect(rows.map(\.lineA) == [1, 2, 3])
        #expect(rows.map(\.lineB) == [1, 2, 3])
    }

    @Test func emptyMainIsAllAdds() {
        let rows = LineDiff.compute("", "x\ny")
        #expect(rows.map(\.kind) == [.add, .add])
        #expect(rows.map(\.lineA) == [nil, nil])
        #expect(rows.map(\.lineB) == [1, 2])
    }

    @Test func emptyWorktreeIsAllDels() {
        let rows = LineDiff.compute("x\ny", "")
        #expect(rows.map(\.kind) == [.del, .del])
        #expect(rows.map(\.lineB) == [nil, nil])
        #expect(rows.map(\.lineA) == [1, 2])
    }

    @Test func singleLineChangeIsDelThenAdd() {
        let rows = LineDiff.compute("a\nB\nc", "a\nb\nc")
        #expect(rows.map(\.kind) == [.context, .del, .add, .context])
        #expect(rows.filter { $0.kind == .add }.map(\.text) == ["b"])
        #expect(rows.filter { $0.kind == .del }.map(\.text) == ["B"])
    }

    @Test func appendedLinesAreAdds() {
        let rows = LineDiff.compute("a", "a\nb\nc")
        #expect(rows.map(\.kind) == [.context, .add, .add])
        #expect(rows.last?.lineB == 3)
    }

    @Test func idsAreUniqueAndSequential() {
        let rows = LineDiff.compute("a\nB", "a\nb")
        #expect(rows.map(\.id) == Array(0..<rows.count))
    }
}
