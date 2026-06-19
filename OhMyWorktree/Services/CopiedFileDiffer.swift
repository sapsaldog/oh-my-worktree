import Foundation

/// Compares a worktree's copied (`.worktreeinclude`) files against the
/// repository's (main worktree's) copies. Stateless; safe to instantiate per call.
final class CopiedFileDiffer: Sendable {

    /// Builds a `CopiedFile` per relative path by reading both copies. A path may
    /// live in either tree: present in main only ⇒ `.missing` (the copy never
    /// happened); present in the worktree only ⇒ `.new`. Only paths absent on both
    /// sides are skipped (defensive — the list is a union scan of both trees).
    /// Result is sorted modified → missing → new → identical.
    func compare(relativePaths: [String], worktreePath: String, repositoryPath: String) -> [CopiedFile] {
        let fm = FileManager.default
        let files: [CopiedFile] = relativePaths.compactMap { rel in
            let worktreeFull = (worktreePath as NSString).appendingPathComponent(rel)
            let mainFull = (repositoryPath as NSString).appendingPathComponent(rel)
            let worktreeData = fm.contents(atPath: worktreeFull)
            let mainData = fm.contents(atPath: mainFull)
            guard worktreeData != nil || mainData != nil else { return nil }
            return CopiedFile.classify(path: rel, mainData: mainData, worktreeData: worktreeData)
        }
        return files.sorted { lhs, rhs in
            lhs.status.sortRank != rhs.status.sortRank
                ? lhs.status.sortRank < rhs.status.sortRank
                : lhs.path < rhs.path
        }
    }
}
