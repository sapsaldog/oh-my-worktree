# Copied Files Diff & Apply-to-Main Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the detail pane's "Copied files" diff-aware — each `.worktreeinclude` copy is compared against the repository's (main worktree's) copy, shown as modified/new/identical, browsable in a searchable glass sheet that drills into a GitHub-style unified diff, with an "Apply to main" that overwrites main's local copy (behind a confirmation).

**Architecture:** All behavior lives in `Models/` + `Services/` and is unit-tested to the repo's 100% gate; all rendering lives in `Views/` (coverage-excluded) and is verified by build + manual smoke. The diff is a content compare (these files are git-ignored, so `git diff` does not apply); "main" is `repository.path`. Apply writes the worktree's bytes back to `repository.path/<relpath>` atomically and never touches Git.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing (`@Suite`/`@Test`/`#expect`), `FileManager`. Design tokens in `OMWColor`/`OMWRadius`/`GlassSheetMetrics`. Reference design: `oh-my-worktree/project/{data,WorktreeWindow,Sheets}.jsx` + `omw.css`.

---

## Design notes locked for this plan

- **Status model:** `enum CopiedFileStatus { case identical, modified, new }` plus a separate
  `CopiedFile.isBinary: Bool`. Binary-identical = `.identical` + `isBinary`; binary-modified =
  `.modified` + `isBinary`. `isClickable == (status != .identical)`. `isChanged == (status != .identical)`.
- **Classification is pure** (`CopiedFile.classify(path:mainData:worktreeData:)`, takes `Data?`/`Data`),
  so it is fully tested without file I/O. `CopiedFileDiffer` only does file reads/writes and calls it.
- **Apply** uses `Data.write(to:options:.atomic)` — atomic overwrite that also creates the file when absent.

## File Structure

**Create (logic — 100% tested):**
- `OhMyWorktree/Models/LineDiff.swift` — `DiffLine` + `LineDiff.compute`
- `OhMyWorktree/Models/CopiedFile.swift` — `CopiedFileStatus`, `CopiedPath`, `CopiedFile` (+ `classify`)
- `OhMyWorktree/Services/CopiedFileDiffer.swift` — `compare`, `applyToMain`
- `OhMyWorktreeTests/LineDiffTests.swift`
- `OhMyWorktreeTests/CopiedFileTests.swift`
- `OhMyWorktreeTests/CopiedFileDifferTests.swift`

**Create (views — coverage-excluded):**
- `OhMyWorktree/Views/Detail/PathLabel.swift`
- `OhMyWorktree/Views/Detail/CopiedFilesBrowser.swift` (sheet: list ↔ diff drill-in, `CopiedFileRow`, `UnifiedDiffView`)
- `OhMyWorktree/Views/Detail/CopiedToast.swift`

**Modify:**
- `OhMyWorktree/Models/WorktreeDetail.swift` — `copiedFiles: [String]` → `[CopiedFile]`
- `OhMyWorktree/ViewModels/WorktreeListViewModel+Creation.swift` — build `[CopiedFile]` in `loadDetail`
- `OhMyWorktree/ViewModels/WorktreeListViewModel.swift` — browser/apply/toast state + glue + `differ`
- `OhMyWorktree/Views/Detail/CopiedFilesSection.swift` — full diff-aware rewrite
- `OhMyWorktree/Views/Detail/DetailPaneView.swift` — forward `onOpenCopiedDiff` / `onBrowseCopied`
- `OhMyWorktree/Views/ContentView.swift` — present browser in `modalOverlay`, apply alert, toast
- `OhMyWorktreeTests/WorktreeDetailTests.swift` — assert new `[CopiedFile]` shape

**No `coverage-exclude.txt` changes.** All new logic is in `Models/`+`Services/` and must hit 100%.

---

### Task 1: Line diff (`DiffLine` + `LineDiff.compute`)

LCS line diff ported from `data.jsx#diffLines`.

**Files:**
- Create: `OhMyWorktree/Models/LineDiff.swift`
- Test: `OhMyWorktreeTests/LineDiffTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OhMyWorktreeTests/LineDiffTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test 2>&1 | grep -i "LineDiffTests\|error:"`
Expected: build/compile failure — `LineDiff` / `DiffLine` are undefined.

- [ ] **Step 3: Write the implementation**

Create `OhMyWorktree/Models/LineDiff.swift`:

```swift
import Foundation

/// One line of a unified diff between two text blobs.
struct DiffLine: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable { case context, add, del }
    let kind: Kind
    let text: String
    /// 1-based line number on the "main" (a) side; nil for added lines.
    let lineA: Int?
    /// 1-based line number on the "worktree" (b) side; nil for deleted lines.
    let lineB: Int?
    /// Stable index assigned at build time (array position).
    let id: Int
}

/// Minimal LCS line diff (port of the prototype's `data.jsx#diffLines`).
enum LineDiff {

    /// Compares `a` (main) against `b` (worktree), line by line.
    /// An empty `a` yields all-adds; an empty `b` yields all-dels.
    static func compute(_ a: String, _ b: String) -> [DiffLine] {
        let aLines = a.components(separatedBy: "\n")
        let bLines = b.components(separatedBy: "\n")

        var raw: [(kind: DiffLine.Kind, text: String, lineA: Int?, lineB: Int?)] = []

        if a.isEmpty {
            for (i, line) in bLines.enumerated() {
                raw.append((.add, line, nil, i + 1))
            }
        } else if b.isEmpty {
            for (i, line) in aLines.enumerated() {
                raw.append((.del, line, i + 1, nil))
            }
        } else {
            let n = aLines.count
            let m = bLines.count
            // dp[i][j] = LCS length of aLines[i...] and bLines[j...]
            var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
            if n > 0 && m > 0 {
                for i in stride(from: n - 1, through: 0, by: -1) {
                    for j in stride(from: m - 1, through: 0, by: -1) {
                        dp[i][j] = aLines[i] == bLines[j]
                            ? dp[i + 1][j + 1] + 1
                            : max(dp[i + 1][j], dp[i][j + 1])
                    }
                }
            }
            var i = 0, j = 0
            while i < n && j < m {
                if aLines[i] == bLines[j] {
                    raw.append((.context, aLines[i], i + 1, j + 1)); i += 1; j += 1
                } else if dp[i + 1][j] >= dp[i][j + 1] {
                    raw.append((.del, aLines[i], i + 1, nil)); i += 1
                } else {
                    raw.append((.add, bLines[j], nil, j + 1)); j += 1
                }
            }
            while i < n { raw.append((.del, aLines[i], i + 1, nil)); i += 1 }
            while j < m { raw.append((.add, bLines[j], nil, j + 1)); j += 1 }
        }

        return raw.enumerated().map { index, r in
            DiffLine(kind: r.kind, text: r.text, lineA: r.lineA, lineB: r.lineB, id: index)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test 2>&1 | grep -i "LineDiffTests\|Test Suite.*passed\|error:"`
Expected: PASS for all `LineDiffTests`.

- [ ] **Step 5: Commit**

```bash
git add OhMyWorktree/Models/LineDiff.swift OhMyWorktreeTests/LineDiffTests.swift
git commit -m "feat: add LineDiff LCS line-diff for copied files"
```

---

### Task 2: `CopiedFileStatus`, `CopiedPath`, and `CopiedFile.classify`

Pure status/diff classification, plus the path-split helper for `PathLabel`.

**Files:**
- Create: `OhMyWorktree/Models/CopiedFile.swift`
- Test: `OhMyWorktreeTests/CopiedFileTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OhMyWorktreeTests/CopiedFileTests.swift`:

```swift
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
        #expect(CopiedFileStatus.identical.isClickable == false)
        #expect(CopiedFileStatus.modified.isClickable)
        #expect(CopiedFileStatus.new.isClickable)
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test 2>&1 | grep -i "CopiedFileTests\|error:"`
Expected: compile failure — `CopiedFile`, `CopiedFileStatus`, `CopiedPath` undefined.

- [ ] **Step 3: Write the implementation**

Create `OhMyWorktree/Models/CopiedFile.swift`:

```swift
import Foundation

/// How a worktree's copied file relates to the repository's (main's) copy.
enum CopiedFileStatus: Equatable, Sendable {
    case identical   // bytes equal
    case modified    // present in both, bytes differ
    case new         // present in the worktree, absent in main

    /// Differs from main (anything worth surfacing / applying).
    var isChanged: Bool { self != .identical }
    /// Has something to open (a diff to view or content to copy back).
    var isClickable: Bool { self != .identical }
    /// Ordering for chips/list: changed first, then new, then identical.
    var sortRank: Int {
        switch self {
        case .modified: 0
        case .new: 1
        case .identical: 2
        }
    }
}

/// Splits a repo-relative path into its directory (with trailing slash) and filename.
enum CopiedPath {
    static func split(_ path: String) -> (dir: String, base: String) {
        guard let slash = path.lastIndex(of: "/") else { return (dir: "", base: path) }
        let after = path.index(after: slash)
        return (dir: String(path[...slash]), base: String(path[after...]))
    }
}

/// A `.worktreeinclude` copied file compared against main, with its line diff.
struct CopiedFile: Equatable, Sendable, Identifiable {
    let path: String
    let status: CopiedFileStatus
    let isBinary: Bool
    let added: Int
    let removed: Int
    let mainContent: String?
    let worktreeContent: String?
    let lines: [DiffLine]

    var id: String { path }

    /// Classifies a copied file from raw bytes. `mainData == nil` ⇒ `.new`.
    /// Non-UTF-8 on either side ⇒ binary (byte-compared, no line preview).
    static func classify(path: String, mainData: Data?, worktreeData: Data) -> CopiedFile {
        let worktreeText = String(data: worktreeData, encoding: .utf8)

        guard let mainData else {
            // New file — not in main.
            if let worktreeText {
                let lines = LineDiff.compute("", worktreeText)
                return CopiedFile(path: path, status: .new, isBinary: false,
                                  added: lines.count, removed: 0,
                                  mainContent: nil, worktreeContent: worktreeText, lines: lines)
            }
            return CopiedFile(path: path, status: .new, isBinary: true,
                              added: 0, removed: 0,
                              mainContent: nil, worktreeContent: nil, lines: [])
        }

        let mainText = String(data: mainData, encoding: .utf8)
        let isBinary = (mainText == nil) || (worktreeText == nil)

        if mainData == worktreeData {
            return CopiedFile(path: path, status: .identical, isBinary: isBinary,
                              added: 0, removed: 0,
                              mainContent: mainText, worktreeContent: worktreeText, lines: [])
        }

        guard !isBinary, let mainText, let worktreeText else {
            return CopiedFile(path: path, status: .modified, isBinary: true,
                              added: 0, removed: 0,
                              mainContent: mainText, worktreeContent: worktreeText, lines: [])
        }

        let lines = LineDiff.compute(mainText, worktreeText)
        return CopiedFile(
            path: path, status: .modified, isBinary: false,
            added: lines.filter { $0.kind == .add }.count,
            removed: lines.filter { $0.kind == .del }.count,
            mainContent: mainText, worktreeContent: worktreeText, lines: lines
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test 2>&1 | grep -i "CopiedFileTests\|error:"`
Expected: PASS for all `CopiedFileTests`.

- [ ] **Step 5: Commit**

```bash
git add OhMyWorktree/Models/CopiedFile.swift OhMyWorktreeTests/CopiedFileTests.swift
git commit -m "feat: add CopiedFile status classification + path split"
```

---

### Task 3: `CopiedFileDiffer` (compare + applyToMain)

File I/O service: reads both copies to build `[CopiedFile]`, and writes a copy back to main.

**Files:**
- Create: `OhMyWorktree/Services/CopiedFileDiffer.swift`
- Test: `OhMyWorktreeTests/CopiedFileDifferTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OhMyWorktreeTests/CopiedFileDifferTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test 2>&1 | grep -i "CopiedFileDifferTests\|error:"`
Expected: compile failure — `CopiedFileDiffer` undefined.

- [ ] **Step 3: Write the implementation**

Create `OhMyWorktree/Services/CopiedFileDiffer.swift`:

```swift
import Foundation

/// Compares a worktree's copied (`.worktreeinclude`) files against the
/// repository's (main worktree's) copies, and applies a worktree copy back to main.
/// Stateless; safe to instantiate per call.
final class CopiedFileDiffer: Sendable {

    /// Builds a `CopiedFile` per relative path by reading both copies.
    /// Paths absent in the worktree are skipped (the list is derived from a
    /// worktree scan, so this is defensive). Result is sorted changed → new → identical.
    func compare(relativePaths: [String], worktreePath: String, repositoryPath: String) -> [CopiedFile] {
        let fm = FileManager.default
        let files: [CopiedFile] = relativePaths.compactMap { rel in
            let worktreeFull = (worktreePath as NSString).appendingPathComponent(rel)
            guard let worktreeData = fm.contents(atPath: worktreeFull) else { return nil }
            let mainFull = (repositoryPath as NSString).appendingPathComponent(rel)
            let mainData = fm.contents(atPath: mainFull)
            return CopiedFile.classify(path: rel, mainData: mainData, worktreeData: worktreeData)
        }
        return files.sorted { lhs, rhs in
            lhs.status.sortRank != rhs.status.sortRank
                ? lhs.status.sortRank < rhs.status.sortRank
                : lhs.path < rhs.path
        }
    }

    /// Overwrites main's local copy of `file` with the worktree's bytes (atomically;
    /// creates the file and parent directories when absent). Never touches Git.
    func applyToMain(_ file: CopiedFile, worktreePath: String, repositoryPath: String) throws {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: (worktreePath as NSString).appendingPathComponent(file.path))
        let dest = URL(fileURLWithPath: (repositoryPath as NSString).appendingPathComponent(file.path))
        let destDir = (dest.path as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        let data = try Data(contentsOf: source)
        try data.write(to: dest, options: .atomic)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test 2>&1 | grep -i "CopiedFileDifferTests\|error:"`
Expected: PASS for all `CopiedFileDifferTests`.

- [ ] **Step 5: Commit**

```bash
git add OhMyWorktree/Services/CopiedFileDiffer.swift OhMyWorktreeTests/CopiedFileDifferTests.swift
git commit -m "feat: add CopiedFileDiffer compare + applyToMain"
```

---

### Task 4: Change `WorktreeDetail.copiedFiles` to `[CopiedFile]` and populate it

Switch the model type and build `[CopiedFile]` in `loadDetail`. Keep the build green by
updating every consumer minimally (the full UI rewrite comes in later tasks).

**Files:**
- Modify: `OhMyWorktree/Models/WorktreeDetail.swift:33-34`
- Modify: `OhMyWorktree/ViewModels/WorktreeListViewModel.swift` (add `differ`)
- Modify: `OhMyWorktree/ViewModels/WorktreeListViewModel+Creation.swift:98-103`
- Modify: `OhMyWorktree/Views/Detail/CopiedFilesSection.swift` (signature only, minimal)
- Test: `OhMyWorktreeTests/WorktreeDetailTests.swift` (add a `[CopiedFile]` assertion)

- [ ] **Step 1: Write/extend the failing test**

In `OhMyWorktreeTests/WorktreeDetailTests.swift`, inside `struct WorktreeDetailModelTests`, add:

```swift
    @Test func copiedFilesHoldClassifiedEntries() {
        let file = CopiedFile.classify(path: ".env",
                                       mainData: Data("A=1".utf8),
                                       worktreeData: Data("A=2".utf8))
        let detail = WorktreeDetail(aheadBehind: nil,
                                    diff: DiffStat(added: 0, removed: 0, files: 0),
                                    commits: [],
                                    copiedFiles: [file])
        #expect(detail.copiedFiles.map(\.status) == [.modified])
        #expect(detail.copiedFiles.first?.path == ".env")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test 2>&1 | grep -i "copiedFilesHoldClassified\|error:"`
Expected: compile failure — `WorktreeDetail.init` still expects `[String]` for `copiedFiles`.

- [ ] **Step 3: Change the model**

In `OhMyWorktree/Models/WorktreeDetail.swift`, replace lines 33-34:

```swift
    /// Files copied into the worktree per `.worktreeinclude` (or `.env*`).
    var copiedFiles: [String] = []
```

with:

```swift
    /// Files copied into the worktree per `.worktreeinclude` (or `.env*`),
    /// each classified against main (the repository copy) for diff display.
    var copiedFiles: [CopiedFile] = []
```

- [ ] **Step 4: Inject the differ into the view model**

In `OhMyWorktree/ViewModels/WorktreeListViewModel.swift`, next to the existing
`let fileCopier: WorktreeFileCopier` stored property (around line 68), add:

```swift
    let differ: CopiedFileDiffer
```

In the same file's `init`, find the parameter list containing
`fileCopier: WorktreeFileCopier = WorktreeFileCopier(),` (around line 90) and add a parameter:

```swift
        differ: CopiedFileDiffer = CopiedFileDiffer(),
```

and in the init body, next to `self.fileCopier = fileCopier` (around line 96), add:

```swift
        self.differ = differ
```

- [ ] **Step 5: Build `[CopiedFile]` in `loadDetail`**

In `OhMyWorktree/ViewModels/WorktreeListViewModel+Creation.swift`, replace lines 98-103:

```swift
        let copier = fileCopier
        let path = worktree.path
        let matches = await Task.detached { copier.includedFiles(in: path) }.value
        // Only files Git ignores were actually copied; committed templates
        // (e.g. .env.example) come with the checkout and don't count.
        detail.copiedFiles = await worktreeManager.gitIgnoredFiles(matches, worktreePath: path)
```

with:

```swift
        let copier = fileCopier
        let differ = self.differ
        let path = worktree.path
        let repoPath = repository.path
        let matches = await Task.detached { copier.includedFiles(in: path) }.value
        // Only files Git ignores were actually copied; committed templates
        // (e.g. .env.example) come with the checkout and don't count.
        let ignored = await worktreeManager.gitIgnoredFiles(matches, worktreePath: path)
        detail.copiedFiles = await Task.detached {
            differ.compare(relativePaths: ignored, worktreePath: path, repositoryPath: repoPath)
        }.value
```

- [ ] **Step 6: Keep `CopiedFilesSection` compiling (minimal)**

In `OhMyWorktree/Views/Detail/CopiedFilesSection.swift`, change the stored property and the
two places that consume the strings so it still builds (it will be fully rewritten in Task 6).

Replace `let files: [String]` (line 6) with:

```swift
    let files: [CopiedFile]
```

Replace the filtered/shown computation in `body` (lines 16-19):

```swift
        let filtered = query.isEmpty
            ? files
            : files.filter { $0.lowercased().contains(query.lowercased()) }
        let shown = (!expanded && many) ? Array(files.prefix(cap)) : filtered
```

with:

```swift
        let names = files.map(\.path)
        let filtered = query.isEmpty
            ? names
            : names.filter { $0.lowercased().contains(query.lowercased()) }
        let shown = (!expanded && many) ? Array(names.prefix(cap)) : filtered
```

(`chips(shown:)` already takes `[String]` and renders `CopiedFileChip(name:)`, so no other change is needed here.)

- [ ] **Step 7: Run the full test scheme to verify green**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test 2>&1 | tail -25`
Expected: build succeeds; all suites PASS (including `copiedFilesHoldClassifiedEntries` and the unchanged `emptyDetailHasNoData`).

- [ ] **Step 8: Commit**

```bash
git add OhMyWorktree/Models/WorktreeDetail.swift \
        OhMyWorktree/ViewModels/WorktreeListViewModel.swift \
        OhMyWorktree/ViewModels/WorktreeListViewModel+Creation.swift \
        OhMyWorktree/Views/Detail/CopiedFilesSection.swift \
        OhMyWorktreeTests/WorktreeDetailTests.swift
git commit -m "feat: classify copied files in detail load ([CopiedFile])"
```

---

### Task 5: View model browser/apply/toast state + glue

Add the state the UI binds to and the thin apply glue (real work is in the tested service).

**Files:**
- Modify: `OhMyWorktree/ViewModels/WorktreeListViewModel.swift`

- [ ] **Step 1: Add observable state**

In `OhMyWorktree/ViewModels/WorktreeListViewModel.swift`, near `var selectedWorktreeDetail: WorktreeDetail?` (line 30), add:

```swift
    /// When non-nil, the copied-files browser sheet is open. `focusedPath`, when
    /// set, opens straight to that file's diff (drill-in); nil shows the list.
    var copiedBrowser: CopiedBrowserState?
    /// A copied file awaiting Apply-to-main confirmation.
    var pendingApply: CopiedFile?
    /// Transient success message shown as a toast after an apply.
    var copiedToast: String?
```

- [ ] **Step 2: Define the state struct + glue methods**

At the end of `OhMyWorktree/ViewModels/WorktreeListViewModel.swift`, before the final closing brace
of the `class`, add:

```swift
    /// Open state for the copied-files browser sheet.
    struct CopiedBrowserState: Equatable {
        var worktree: Worktree
        var focusedPath: String?
    }

    /// Opens the browser to the full list for `worktree`.
    func browseCopiedFiles(for worktree: Worktree) {
        copiedBrowser = CopiedBrowserState(worktree: worktree, focusedPath: nil)
    }

    /// Opens the browser straight to `file`'s diff for `worktree`.
    func openCopiedDiff(_ file: CopiedFile, for worktree: Worktree) {
        copiedBrowser = CopiedBrowserState(worktree: worktree, focusedPath: file.path)
    }

    /// Applies `file` (worktree → main), reloads the detail so statuses refresh,
    /// and shows a toast. Surfaces failures through the standard error alert.
    func applyCopiedFileToMain(_ file: CopiedFile, in worktree: Worktree) async {
        guard let repository else { return }
        let differ = self.differ
        let worktreePath = worktree.path
        let repoPath = repository.path
        do {
            try await Task.detached {
                try differ.applyToMain(file, worktreePath: worktreePath, repositoryPath: repoPath)
            }.value
            await loadDetail(for: worktree)
            copiedToast = "Applied \((file.path as NSString).lastPathComponent) to main"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build 2>&1 | tail -15`
Expected: BUILD SUCCEEDED (new state is unused for now — that is expected; it is wired in Task 7).

- [ ] **Step 4: Run the test scheme (no behavior change, must stay green)**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test 2>&1 | tail -8`
Expected: all suites PASS.

- [ ] **Step 5: Commit**

```bash
git add OhMyWorktree/ViewModels/WorktreeListViewModel.swift
git commit -m "feat: copied-files browser/apply/toast state in view model"
```

---

### Task 6: `PathLabel` + diff-aware `CopiedFilesSection` rewrite

Replace the inline expand/filter section with the prototype's diff-aware header + status chips +
"View all" affordance. Views are coverage-excluded — verify by build + manual smoke.

**Files:**
- Create: `OhMyWorktree/Views/Detail/PathLabel.swift`
- Modify: `OhMyWorktree/Views/Detail/CopiedFilesSection.swift` (full rewrite)

- [ ] **Step 1: Create `PathLabel`**

Create `OhMyWorktree/Views/Detail/PathLabel.swift`:

```swift
import SwiftUI

/// Renders a repo-relative path so the directory truncates with an ellipsis while
/// the filename is always fully visible. Full path shown on hover (CSS `.pl`).
/// Font/size come from the caller (`.font(...)`); only the directory is recolored
/// to tertiary — the filename inherits the surrounding foreground style.
struct PathLabel: View {
    let path: String

    var body: some View {
        let parts = CopiedPath.split(path)
        HStack(spacing: 0) {
            if !parts.dir.isEmpty {
                Text(parts.dir)
                    .foregroundStyle(OMWColor.labelTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(0)
            }
            Text(parts.base)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .help(path)
    }
}
```

- [ ] **Step 2: Rewrite `CopiedFilesSection`**

Replace the entire contents of `OhMyWorktree/Views/Detail/CopiedFilesSection.swift` with:

```swift
import SwiftUI

/// Detail-pane "Copied files" section: a compact one-line header with a changed
/// count, status chips (modified `+N −N` / `new` / dimmed identical), and a
/// "View all" button that opens the searchable browser sheet.
struct CopiedFilesSection: View {
    let files: [CopiedFile]
    var onOpenDiff: (CopiedFile) -> Void = { _ in }
    var onBrowseAll: () -> Void = {}

    private let cap = 5

    private var sorted: [CopiedFile] {
        files.sorted { lhs, rhs in
            lhs.status.sortRank != rhs.status.sortRank
                ? lhs.status.sortRank < rhs.status.sortRank
                : lhs.path < rhs.path
        }
    }
    private var changedCount: Int { files.filter { $0.status.isChanged }.count }

    var body: some View {
        let many = files.count > cap
        let shown = many ? Array(sorted.prefix(cap)) : sorted

        VStack(alignment: .leading, spacing: 10) {
            header
            FlowLayout(spacing: 6) {
                ForEach(shown) { chip($0) }
            }
            if many { viewAllButton }
        }
        .padding(.init(top: 14, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(OMWColor.separator).frame(height: 0.5) }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Text("Copied files")
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(OMWColor.labelTertiary)
                Text("\(files.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OMWColor.labelTertiary)
                if changedCount > 0 {
                    Text("· \(changedCount) changed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OMWColor.sysOrange)
                }
            }
            Spacer()
            Text(".worktreeinclude")
                .font(.omwMono(10))
                .foregroundStyle(OMWColor.labelQuaternary)
        }
    }

    @ViewBuilder
    private func chip(_ file: CopiedFile) -> some View {
        let clickable = file.status.isClickable
        Button { if clickable { onOpenDiff(file) } } label: {
            HStack(spacing: 5) {
                switch file.status {
                case .modified: Circle().fill(OMWColor.sysOrange).frame(width: 6, height: 6)
                case .new: Circle().fill(OMWColor.sysGreen).frame(width: 6, height: 6)
                case .identical: Image(systemName: "doc").font(.system(size: 11))
                }
                PathLabel(path: file.path)
                    .font(.omwMono(11, weight: .medium))
                if file.status == .modified {
                    HStack(spacing: 4) {
                        Text("+\(file.added)").foregroundStyle(OMWColor.sysGreen)
                        Text("−\(file.removed)").foregroundStyle(OMWColor.sysRed)
                    }
                    .font(.omwMono(11, weight: .bold))
                } else if file.status == .new {
                    Text("new")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(OMWColor.sysGreen)
                }
            }
            .foregroundStyle(file.status == .identical ? OMWColor.labelSecondary : OMWColor.labelPrimary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(chipBackground(file.status), in: Capsule())
            .opacity(file.status == .identical ? 0.48 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!clickable)
        .help(clickable ? "\(file.path) — click to compare with main" : "\(file.path) — identical to main")
    }

    private func chipBackground(_ status: CopiedFileStatus) -> Color {
        switch status {
        case .modified: OMWColor.sysOrange.opacity(0.15)
        case .new: OMWColor.sysGreen.opacity(0.15)
        case .identical: OMWColor.fillTertiary
        }
    }

    private var viewAllButton: some View {
        Button(action: onBrowseAll) {
            HStack(spacing: 7) {
                Image(systemName: "list.bullet").font(.system(size: 13))
                Text("View all \(files.count) files").font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(OMWColor.labelTertiary)
            }
            .foregroundStyle(OMWColor.labelSecondary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(OMWColor.fillTertiary, in: RoundedRectangle(cornerRadius: OMWRadius.md))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build 2>&1 | tail -15`
Expected: BUILD SUCCEEDED. (`DetailPaneView` still calls `CopiedFilesSection(files:)`; the new
closure params default to no-ops, so it compiles. Clicking does nothing until Task 8.)

- [ ] **Step 4: Run swiftlint**

Run: `swiftlint lint --quiet OhMyWorktree/Views/Detail/CopiedFilesSection.swift OhMyWorktree/Views/Detail/PathLabel.swift`
Expected: no violations.

- [ ] **Step 5: Commit**

```bash
git add OhMyWorktree/Views/Detail/PathLabel.swift OhMyWorktree/Views/Detail/CopiedFilesSection.swift
git commit -m "feat: diff-aware copied-files chips + PathLabel"
```

---

### Task 7: `CopiedFilesBrowser` sheet (list ↔ diff drill-in)

The single glass sheet: searchable list with a "Changed only" filter that drills into a
GitHub-style unified diff and applies back to main. Includes `CopiedFileRow` and `UnifiedDiffView`.

**Files:**
- Create: `OhMyWorktree/Views/Detail/CopiedFilesBrowser.swift`

- [ ] **Step 1: Create the browser sheet**

Create `OhMyWorktree/Views/Detail/CopiedFilesBrowser.swift`:

```swift
import SwiftUI

/// One glass sheet that browses a worktree's copied files and drills into a
/// unified diff vs. main. `focusedPath` (re-resolved against `files` each render so
/// it reflects applied changes) opens straight to that file's diff.
struct CopiedFilesBrowser: View {
    let files: [CopiedFile]
    @Binding var focusedPath: String?
    var onApply: (CopiedFile) -> Void
    var onClose: () -> Void

    @Environment(\.omwAccent) private var accent
    @State private var query = ""
    @State private var changedOnly = false

    private var changedCount: Int { files.filter { $0.status.isChanged }.count }

    private var active: CopiedFile? {
        guard let focusedPath else { return nil }
        return files.first { $0.path == focusedPath }
    }

    private var sorted: [CopiedFile] {
        files.sorted { lhs, rhs in
            lhs.status.sortRank != rhs.status.sortRank
                ? lhs.status.sortRank < rhs.status.sortRank
                : lhs.path < rhs.path
        }
    }

    private var filtered: [CopiedFile] {
        sorted.filter { file in
            (!changedOnly || file.status.isChanged)
                && (query.isEmpty || file.path.lowercased().contains(query.lowercased()))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let active {
                diffView(active)
            } else {
                listView
            }
        }
        .frame(width: 520)
        .frame(maxHeight: 560)
        .glassSheet()
        .tint(accent)
        .onExitCommand { focusedPath != nil ? (focusedPath = nil) : onClose() }
    }

    // MARK: List

    private var listView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Text("Copied files").font(.system(size: 14, weight: .bold))
                    Text("\(files.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(OMWColor.labelTertiary)
                    if changedCount > 0 {
                        Text("· \(changedCount) changed vs. main")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(OMWColor.sysOrange)
                    }
                }
                Spacer()
                Text(".worktreeinclude").font(.omwMono(11)).foregroundStyle(OMWColor.labelQuaternary)
            }
            .padding(.init(top: 16, leading: 18, bottom: 0, trailing: 18))

            HStack(spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(OMWColor.labelTertiary)
                    TextField("Filter files…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                }
                .padding(.horizontal, 10).frame(height: 28)
                .background(OMWColor.controlBg, in: Capsule())
                .overlay(Capsule().strokeBorder(OMWColor.separator, lineWidth: 0.5))

                if changedCount > 0 {
                    Button { changedOnly.toggle() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: changedOnly ? "checkmark" : "arrow.left.arrow.right").font(.system(size: 12))
                            Text("Changed only").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(changedOnly ? OMWColor.onAccent : OMWColor.labelSecondary)
                        .padding(.horizontal, 11).frame(height: 28)
                        .background(changedOnly ? AnyShapeStyle(accent) : AnyShapeStyle(OMWColor.fillTertiary), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.init(top: 12, leading: 18, bottom: 4, trailing: 18))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { file in
                        CopiedFileRow(file: file) { focusedPath = file.path }
                    }
                    if filtered.isEmpty {
                        Text("No files match “\(query)”.")
                            .font(.system(size: 13)).foregroundStyle(OMWColor.labelTertiary)
                            .frame(maxWidth: .infinity).padding(.vertical, 26)
                    }
                }
                .padding(.init(top: 6, leading: 12, bottom: 12, trailing: 12))
            }

            footer(hint: "Click a changed file to view its diff and apply it back to main.") {
                Button("Done", action: onClose)
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Diff drill-in

    private func diffView(_ file: CopiedFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { focusedPath = nil } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        Text("All files").font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(accent)
                    .padding(.init(top: 4, leading: 4, bottom: 4, trailing: 8))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(file.status == .new ? "new file — not in main" : "comparing vs. main")
                    .font(.omwMono(11)).foregroundStyle(OMWColor.labelQuaternary)
            }
            .padding(.init(top: 12, leading: 14, bottom: 0, trailing: 14))

            PathLabel(path: file.path)
                .font(.omwMono(14, weight: .bold))
                .foregroundStyle(OMWColor.labelPrimary)
                .padding(.init(top: 8, leading: 18, bottom: 0, trailing: 18))

            UnifiedDiffView(file: file)
                .padding(.init(top: 12, leading: 18, bottom: 4, trailing: 18))

            footer(hint: "Updates main’s local copy only — nothing is committed to Git.") {
                Button { onApply(file) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.to.line").font(.system(size: 13))
                        Text(file.status == .new ? "Copy to main" : "Apply to main").font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
            }
        }
    }

    // MARK: Footer

    private func footer(hint: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 14) {
            Text(hint).font(.system(size: 11)).foregroundStyle(OMWColor.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.init(top: 12, leading: 18, bottom: 14, trailing: 18))
        .overlay(alignment: .top) { Rectangle().fill(OMWColor.separator).frame(height: 0.5) }
    }
}

/// A full-width row in the browser list: status dot · path · `+N −N`/`new`/`identical` · chevron.
private struct CopiedFileRow: View {
    let file: CopiedFile
    var onSelect: () -> Void

    var body: some View {
        let clickable = file.status.isClickable
        Button { if clickable { onSelect() } } label: {
            HStack(spacing: 9) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                PathLabel(path: file.path).font(.omwMono(12.5, weight: .medium)).foregroundStyle(OMWColor.labelPrimary)
                Spacer(minLength: 8)
                switch file.status {
                case .modified:
                    HStack(spacing: 4) {
                        Text("+\(file.added)").foregroundStyle(OMWColor.sysGreen)
                        Text("−\(file.removed)").foregroundStyle(OMWColor.sysRed)
                    }
                    .font(.omwMono(12, weight: .bold))
                case .new:
                    Text("new").font(.system(size: 10, weight: .bold)).textCase(.uppercase)
                        .tracking(0.4).foregroundStyle(OMWColor.sysGreen)
                case .identical:
                    Text("identical").font(.system(size: 10, weight: .medium)).foregroundStyle(OMWColor.labelTertiary)
                }
                if clickable {
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(OMWColor.labelTertiary)
                }
            }
            .padding(.horizontal, 11).frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OMWColor.fillTertiary.opacity(0.0001))   // hit area
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!clickable)
        .opacity(clickable ? 1 : 0.55)
    }

    private var dotColor: Color {
        switch file.status {
        case .modified: OMWColor.sysOrange
        case .new: OMWColor.sysGreen
        case .identical: OMWColor.labelQuaternary
        }
    }
}

/// GitHub-style unified diff: line-number gutters · +/− sign · code, red/green tinted.
/// Binary files (no line preview) show a placeholder instead.
private struct UnifiedDiffView: View {
    let file: CopiedFile

    var body: some View {
        if file.isBinary {
            HStack(spacing: 7) {
                Image(systemName: "doc.badge.gearshape").font(.system(size: 13))
                Text("Binary file — no preview").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(OMWColor.labelTertiary)
            .frame(maxWidth: .infinity).padding(.vertical, 36)
            .background(OMWColor.fillQuaternary, in: RoundedRectangle(cornerRadius: OMWRadius.md))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(file.lines) { line in row(line) }
                }
            }
            .frame(maxHeight: 380)
            .overlay(RoundedRectangle(cornerRadius: OMWRadius.md).strokeBorder(OMWColor.separator, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: OMWRadius.md))
        }
    }

    private func row(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            gutter(line.lineA)
            gutter(line.lineB).overlay(alignment: .trailing) {
                Rectangle().fill(OMWColor.separator).frame(width: 0.5)
            }
            Text(sign(line.kind)).frame(width: 16).foregroundStyle(signColor(line.kind))
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(OMWColor.labelPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 10).padding(.leading, 5)
        }
        .font(.omwMono(11))
        .padding(.vertical, 1)
        .background(rowBackground(line.kind))
    }

    private func gutter(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "")
            .font(.omwMono(10)).foregroundStyle(OMWColor.labelQuaternary)
            .frame(width: 34, alignment: .trailing).padding(.trailing, 6)
    }

    private func sign(_ kind: DiffLine.Kind) -> String {
        switch kind { case .add: "+"; case .del: "−"; case .context: "" }
    }
    private func signColor(_ kind: DiffLine.Kind) -> Color {
        switch kind { case .add: OMWColor.sysGreen; case .del: OMWColor.sysRed; case .context: OMWColor.labelTertiary }
    }
    private func rowBackground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .add: OMWColor.sysGreen.opacity(0.13)
        case .del: OMWColor.sysRed.opacity(0.12)
        case .context: Color.clear
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build 2>&1 | tail -15`
Expected: BUILD SUCCEEDED. (Not presented anywhere yet — wired in Task 8.)

- [ ] **Step 3: Run swiftlint**

Run: `swiftlint lint --quiet OhMyWorktree/Views/Detail/CopiedFilesBrowser.swift`
Expected: no violations. (If a type-length/line-length warning appears, split `UnifiedDiffView`
into its own file `OhMyWorktree/Views/Detail/UnifiedDiffView.swift` and re-run.)

- [ ] **Step 4: Commit**

```bash
git add OhMyWorktree/Views/Detail/CopiedFilesBrowser.swift
git commit -m "feat: CopiedFilesBrowser sheet with drill-in unified diff"
```

---

### Task 8: Wire everything (DetailPane callbacks · browser presentation · apply alert · toast)

Connect the section's callbacks to the view model, present the browser in `modalOverlay`, add the
apply confirmation alert and the success toast.

**Files:**
- Create: `OhMyWorktree/Views/Detail/CopiedToast.swift`
- Modify: `OhMyWorktree/Views/Detail/DetailPaneView.swift`
- Modify: `OhMyWorktree/Views/ContentView.swift`

- [ ] **Step 1: Create the toast view**

Create `OhMyWorktree/Views/Detail/CopiedToast.swift`:

```swift
import SwiftUI

/// A transient success pill pinned near the bottom of the window. Auto-dismisses
/// ~2.4s after `message` becomes non-nil by clearing the binding.
struct CopiedToast: View {
    @Binding var message: String?

    var body: some View {
        VStack {
            Spacer()
            if let message {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(OMWColor.sysGreen)
                    Text(message).font(.system(size: 12, weight: .medium)).foregroundStyle(OMWColor.labelPrimary)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .glassEffect(.regular, in: Capsule())
                .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
                .padding(.bottom, 46)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(2.4))
                    self.message = nil
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: message)
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Forward callbacks through `DetailPaneView`**

In `OhMyWorktree/Views/Detail/DetailPaneView.swift`, add two stored properties after
`var onOpenPR: () -> Void` (line 20):

```swift
    var onOpenCopiedDiff: (CopiedFile) -> Void = { _ in }
    var onBrowseCopied: () -> Void = {}
```

Then replace the copied-files line in `content(_:)` (line 71-73):

```swift
            if let copied = detail?.copiedFiles, !copied.isEmpty {
                CopiedFilesSection(files: copied)
            }
```

with:

```swift
            if let copied = detail?.copiedFiles, !copied.isEmpty {
                CopiedFilesSection(files: copied, onOpenDiff: onOpenCopiedDiff, onBrowseAll: onBrowseCopied)
            }
```

- [ ] **Step 3: Pass view-model handlers from `ContentView`**

In `OhMyWorktree/Views/ContentView.swift`, in `worktreeColumns`, extend the `DetailPaneView(...)`
call (lines 151-161) by adding these two arguments after the `onOpenPR:` closure:

```swift
            onOpenCopiedDiff: { file in
                if let wt = selectedWorktree { worktreeViewModel.openCopiedDiff(file, for: wt) }
            },
            onBrowseCopied: {
                if let wt = selectedWorktree { worktreeViewModel.browseCopiedFiles(for: wt) }
            }
```

- [ ] **Step 4: Present the browser in `modalOverlay`**

In `OhMyWorktree/Views/ContentView.swift`, add a branch to `modalOverlay` (after the
`isShowingImportPR` branch, before `modalOverlay`'s closing brace, around line 252):

```swift
        } else if let browser = worktreeViewModel.copiedBrowser {
            glassModal {
                CopiedFilesBrowser(
                    files: worktreeViewModel.selectedWorktreeDetail?.copiedFiles ?? [],
                    focusedPath: Binding(
                        get: { worktreeViewModel.copiedBrowser?.focusedPath },
                        set: { worktreeViewModel.copiedBrowser?.focusedPath = $0 }
                    ),
                    onApply: { file in worktreeViewModel.pendingApply = file },
                    onClose: { worktreeViewModel.copiedBrowser = nil }
                )
                .environment(\.omwAccent, accent)
                .id(browser.worktree.id)
            }
        }
```

- [ ] **Step 5: Add the toast overlay**

In `OhMyWorktree/Views/ContentView.swift`, inside the top-level `ZStack` in `body`, add
`CopiedToast` after `modalOverlay` (line 30):

```swift
            CopiedToast(message: Binding(
                get: { worktreeViewModel.copiedToast },
                set: { worktreeViewModel.copiedToast = $0 }
            ))
            .zIndex(30)
```

- [ ] **Step 6: Add the apply-confirmation alert**

In `OhMyWorktree/Views/ContentView.swift`, after the existing `repoPendingRemoval` `.alert`
(ends ~line 91), add another `.alert`:

```swift
        .alert(
            worktreeViewModel.pendingApply.map { "Apply \(($0.path as NSString).lastPathComponent) to main?" } ?? "",
            isPresented: Binding(
                get: { worktreeViewModel.pendingApply != nil },
                set: { if !$0 { worktreeViewModel.pendingApply = nil } }
            ),
            presenting: worktreeViewModel.pendingApply
        ) { file in
            Button(file.status == .new ? "Copy to main" : "Apply to main", role: .destructive) {
                let target = worktreeViewModel.copiedBrowser?.worktree
                worktreeViewModel.pendingApply = nil
                if let target {
                    Task { await worktreeViewModel.applyCopiedFileToMain(file, in: target) }
                }
            }
            Button("Cancel", role: .cancel) { worktreeViewModel.pendingApply = nil }
        } message: { file in
            Text("Overwrites main’s local copy of \(file.path) with this worktree’s version. "
                + "This updates the file on disk only — nothing is committed to Git.")
        }
```

- [ ] **Step 7: Build and run the full test scheme**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build 2>&1 | tail -15`
Expected: BUILD SUCCEEDED.

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test 2>&1 | tail -10`
Expected: all suites PASS.

- [ ] **Step 8: swiftlint**

Run: `swiftlint lint --quiet OhMyWorktree/Views/ContentView.swift OhMyWorktree/Views/Detail/DetailPaneView.swift OhMyWorktree/Views/Detail/CopiedToast.swift`
Expected: no violations.

- [ ] **Step 9: Commit**

```bash
git add OhMyWorktree/Views/Detail/CopiedToast.swift \
        OhMyWorktree/Views/Detail/DetailPaneView.swift \
        OhMyWorktree/Views/ContentView.swift
git commit -m "feat: wire copied-files browser, apply alert, and toast"
```

---

### Task 9: Coverage gate + final verification

- [ ] **Step 1: Run the coverage gate**

Run: `scripts/coverage.sh`
Expected: PASS. The new `Models/LineDiff.swift`, `Models/CopiedFile.swift`, and
`Services/CopiedFileDiffer.swift` must each report 100%. If any line is uncovered, add a test
case for it (do NOT add to `coverage-exclude.txt`). New `Views/**` files are already excluded.

- [ ] **Step 2: Full lint + test (pre-commit gate from CLAUDE.md)**

Run: `swiftlint lint`
Expected: no violations.

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test 2>&1 | tail -10`
Expected: TEST SUCCEEDED.

- [ ] **Step 3: Manual smoke (record results)**

Build & run the app. With a repo that has a `feature/*` worktree containing copied `.env`/config files:
1. Edit a copied `.env` in the worktree so it differs from the repo copy.
2. Reselect the worktree → its chip shows an orange dot + `+N −N`; header shows `· M changed`.
3. Click the changed chip → browser opens straight to that file's unified diff.
4. `‹ All files` → list; type in Filter; toggle `Changed only`.
5. Open a `new` file (in worktree, not in repo) → diff shows all-adds, button says `Copy to main`.
6. `Apply to main` → confirmation alert → confirm → toast appears, browser returns to list, the
   row/chip flips to `identical`; verify the repo's copy now matches on disk.
7. `Esc` from the list closes the sheet.

- [ ] **Step 4: Final commit (if any smoke fixes were needed)**

```bash
git add -A
git commit -m "test: verify copied-files diff coverage + smoke fixes"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** status model (T2) · LCS diff (T1) · differ compare/apply (T3) · model type
  change + load (T4) · VM state/glue (T5) · diff-aware section + PathLabel (T6) · browser sheet +
  unified diff + binary placeholder (T7) · presentation + apply alert + toast (T8) · 100% gate +
  smoke (T9). Binary handling: T2 `classify*Binary` + T7 `UnifiedDiffView` placeholder. Long paths:
  `PathLabel` (T6). Centered glass sheet: `.glassSheet()` + `glassModal` (T7/T8).
- **Placeholder scan:** none — every code step contains full code.
- **Type consistency:** `CopiedFileStatus{identical,modified,new}` + `isBinary` used identically in
  T2/T4/T6/T7; `CopiedFile.classify(path:mainData:worktreeData:)`, `CopiedFileDiffer.compare(relativePaths:worktreePath:repositoryPath:)`
  / `applyToMain(_:worktreePath:repositoryPath:)`, and VM `browseCopiedFiles`/`openCopiedDiff`/
  `applyCopiedFileToMain`/`copiedBrowser`/`pendingApply`/`copiedToast` are referenced consistently
  across tasks.
```
