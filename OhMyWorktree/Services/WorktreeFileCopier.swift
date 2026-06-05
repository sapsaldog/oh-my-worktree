import Darwin
import Foundation

final class WorktreeFileCopier: Sendable {

    struct CopyResult {
        let copiedFiles: [String]
        let errors: [String]
    }

    private static let excludedDirs: Set<String> = [
        "node_modules", ".git", ".omc", ".claude",
        "dist", "build", ".next", ".nuxt", ".output"
    ]

    /// Copies files from the repository to a new worktree.
    /// If `.worktreeinclude` exists, uses its glob patterns. Otherwise falls back to `.env*` matching.
    func copyFiles(from repositoryPath: String, to worktreePath: String) -> CopyResult {
        let fileManager = FileManager.default
        var copiedFiles: [String] = []
        var errors: [String] = []

        let patterns = loadPatterns(repositoryPath: repositoryPath)
        let matchingFiles: [String]

        if let patterns {
            // .worktreeinclude exists — use its patterns (empty file = no copies)
            matchingFiles = findMatchingFiles(in: repositoryPath, patterns: patterns)
        } else {
            // Legacy fallback — copy .env* files
            matchingFiles = findEnvFiles(in: repositoryPath)
        }

        for relativePath in matchingFiles {
            let sourcePath = (repositoryPath as NSString).appendingPathComponent(relativePath)
            let destPath = (worktreePath as NSString).appendingPathComponent(relativePath)

            guard !fileManager.fileExists(atPath: destPath) else { continue }

            let destDir = (destPath as NSString).deletingLastPathComponent
            do {
                try fileManager.createDirectory(atPath: destDir, withIntermediateDirectories: true)
                try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
                copiedFiles.append(relativePath)
            } catch {
                errors.append("\(relativePath): \(error.localizedDescription)")
            }
        }

        return CopyResult(copiedFiles: copiedFiles, errors: errors)
    }

    /// Lists files in `worktreePath` matching its `.worktreeinclude` patterns
    /// (or `.env*` when no include file) — the files copied into the worktree.
    func includedFiles(in worktreePath: String) -> [String] {
        if let patterns = loadPatterns(repositoryPath: worktreePath) {
            return findMatchingFiles(in: worktreePath, patterns: patterns)
        }
        return findEnvFiles(in: worktreePath)
    }

    // MARK: - .worktreeinclude Parser

    /// Returns parsed patterns if `.worktreeinclude` exists, or `nil` to signal legacy fallback.
    private func loadPatterns(repositoryPath: String) -> [String]? {
        let filePath = (repositoryPath as NSString).appendingPathComponent(".worktreeinclude")
        guard let data = FileManager.default.contents(atPath: filePath),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    // MARK: - Pattern-Based File Search

    private func findMatchingFiles(in directoryPath: String, patterns: [String]) -> [String] {
        guard !patterns.isEmpty else { return [] }

        let fileManager = FileManager.default
        var matched: [String] = []

        guard let enumerator = fileManager.enumerator(atPath: directoryPath) else {
            return []
        }

        while let relativePath = enumerator.nextObject() as? String {
            let fileName = (relativePath as NSString).lastPathComponent

            if Self.excludedDirs.contains(fileName) {
                enumerator.skipDescendants()
                continue
            }

            let fullPath = (directoryPath as NSString).appendingPathComponent(relativePath)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }

            for pattern in patterns where matchesPattern(relativePath: relativePath, pattern: pattern) {
                matched.append(relativePath)
                break
            }
        }

        return matched.sorted()
    }

    // MARK: - fnmatch-Based Pattern Matching

    /// Matches a relative path against a glob pattern using `Darwin.fnmatch`.
    /// - No `/` in pattern → match against filename only (e.g. `.env*`)
    /// - `**/` prefix → match tail against relative path
    /// - Otherwise → match full relative path with `FNM_PATHNAME`
    private func matchesPattern(relativePath: String, pattern: String) -> Bool {
        let fileName = (relativePath as NSString).lastPathComponent

        if pattern.hasPrefix("**/") {
            // e.g. "**/*.local.json" → match "*.local.json" against every suffix
            let tailPattern = String(pattern.dropFirst(3))
            return matchesTail(relativePath: relativePath, tailPattern: tailPattern)
        }

        if !pattern.contains("/") {
            // Simple filename pattern — match against filename only
            return Darwin.fnmatch(pattern, fileName, 0) == 0
        }

        // Path pattern — match full relative path
        return Darwin.fnmatch(pattern, relativePath, FNM_PATHNAME) == 0
    }

    /// For `**/tail` patterns, checks if any suffix of the relative path matches.
    private func matchesTail(relativePath: String, tailPattern: String) -> Bool {
        // Try matching against the full relative path
        if Darwin.fnmatch(tailPattern, relativePath, FNM_PATHNAME) == 0 {
            return true
        }

        // Try matching against each path suffix (includes filename-only)
        let components = relativePath.components(separatedBy: "/")
        for i in 1..<components.count {
            let suffix = components[i...].joined(separator: "/")
            if Darwin.fnmatch(tailPattern, suffix, FNM_PATHNAME) == 0 {
                return true
            }
        }

        return false
    }

    // MARK: - Legacy .env File Search

    private func findEnvFiles(in directoryPath: String) -> [String] {
        let fileManager = FileManager.default
        var envFiles: [String] = []

        guard let enumerator = fileManager.enumerator(atPath: directoryPath) else {
            return []
        }

        while let relativePath = enumerator.nextObject() as? String {
            let fileName = (relativePath as NSString).lastPathComponent

            if Self.excludedDirs.contains(fileName) {
                enumerator.skipDescendants()
                continue
            }

            guard fileName.hasPrefix(".env") else { continue }

            let fullPath = (directoryPath as NSString).appendingPathComponent(relativePath)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                envFiles.append(relativePath)
            }
        }

        return envFiles.sorted()
    }
}
