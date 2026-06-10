import Foundation

/// How a worktree's copied file relates to the repository's (main's) copy.
enum CopiedFileStatus: Equatable, Sendable {
    case identical   // bytes equal
    case modified    // present in both, bytes differ
    case new         // present in the worktree, absent in main
    case missing     // present in main, absent in the worktree (the copy never happened)

    /// Differs from main (anything worth surfacing / applying).
    var isChanged: Bool { self != .identical }
    /// Has something to open (a diff to view or content to copy back).
    var isClickable: Bool { self != .identical }
    /// Ordering for chips/list: modified → missing → new → identical.
    var sortRank: Int {
        switch self {
        case .modified: 0
        case .missing: 1
        case .new: 2
        case .identical: 3
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

    /// Classifies a copied file from raw bytes.
    /// `worktreeData == nil` ⇒ `.missing` (in main, never copied into the worktree);
    /// `mainData == nil` ⇒ `.new` (in the worktree, absent in main).
    /// Non-UTF-8 on either present side ⇒ binary (byte-compared, no line preview).
    static func classify(path: String, mainData: Data?, worktreeData: Data?) -> CopiedFile {
        guard let worktreeData else {
            return classifyMissing(path: path, mainData: mainData)
        }
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

    /// A file present in main but absent from the worktree (the `.worktreeinclude`
    /// copy never happened): main's content shown as removed lines, or a binary /
    /// empty placeholder when main is non-UTF-8 or absent.
    private static func classifyMissing(path: String, mainData: Data?) -> CopiedFile {
        guard let mainData, let mainText = String(data: mainData, encoding: .utf8) else {
            return CopiedFile(path: path, status: .missing, isBinary: mainData != nil,
                              added: 0, removed: 0,
                              mainContent: nil, worktreeContent: nil, lines: [])
        }
        let lines = LineDiff.compute(mainText, "")
        return CopiedFile(path: path, status: .missing, isBinary: false,
                          added: 0, removed: lines.count,
                          mainContent: mainText, worktreeContent: nil, lines: lines)
    }
}
