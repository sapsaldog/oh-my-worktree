import Foundation

/// Compares a worktree's copied (`.worktreeinclude`) files against the
/// repository's (main worktree's) copies, and applies a worktree copy back to main.
/// Stateless; safe to instantiate per call.
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

    /// Copies main's local copy of `file` into the worktree (atomically; creates the
    /// file and parent directories when absent). The inverse of `applyToMain`, for
    /// `.missing` files — performs the `.worktreeinclude` copy that never ran. Never
    /// touches Git.
    func applyToWorktree(_ file: CopiedFile, worktreePath: String, repositoryPath: String) throws {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: (repositoryPath as NSString).appendingPathComponent(file.path))
        let dest = URL(fileURLWithPath: (worktreePath as NSString).appendingPathComponent(file.path))
        let destDir = (dest.path as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        let data = try Data(contentsOf: source)
        try data.write(to: dest, options: .atomic)
    }
}
