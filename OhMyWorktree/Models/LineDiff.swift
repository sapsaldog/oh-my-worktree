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

        let rows: [Row]
        if a.isEmpty {
            rows = bLines.enumerated().map { Row(kind: .add, text: $0.element, lineA: nil, lineB: $0.offset + 1) }
        } else if b.isEmpty {
            rows = aLines.enumerated().map { Row(kind: .del, text: $0.element, lineA: $0.offset + 1, lineB: nil) }
        } else {
            rows = reconstruct(aLines, bLines, lcs: lcsLengths(aLines, bLines))
        }

        return rows.enumerated().map { index, row in
            DiffLine(kind: row.kind, text: row.text, lineA: row.lineA, lineB: row.lineB, id: index)
        }
    }

    private struct Row {
        let kind: DiffLine.Kind
        let text: String
        let lineA: Int?
        let lineB: Int?
    }

    /// `dp[i][j]` = LCS length of `aLines[i...]` and `bLines[j...]`.
    private static func lcsLengths(_ aLines: [String], _ bLines: [String]) -> [[Int]] {
        let n = aLines.count, m = bLines.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = aLines[i] == bLines[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        return dp
    }

    /// Walks the LCS table to produce context/add/del rows.
    private static func reconstruct(_ aLines: [String], _ bLines: [String], lcs dp: [[Int]]) -> [Row] {
        let n = aLines.count, m = bLines.count
        var rows: [Row] = []
        var i = 0, j = 0
        while i < n && j < m {
            if aLines[i] == bLines[j] {
                rows.append(Row(kind: .context, text: aLines[i], lineA: i + 1, lineB: j + 1)); i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                rows.append(Row(kind: .del, text: aLines[i], lineA: i + 1, lineB: nil)); i += 1
            } else {
                rows.append(Row(kind: .add, text: bLines[j], lineA: nil, lineB: j + 1)); j += 1
            }
        }
        while i < n { rows.append(Row(kind: .del, text: aLines[i], lineA: i + 1, lineB: nil)); i += 1 }
        while j < m { rows.append(Row(kind: .add, text: bLines[j], lineA: nil, lineB: j + 1)); j += 1 }
        return rows
    }
}
