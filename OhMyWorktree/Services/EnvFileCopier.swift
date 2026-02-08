import Foundation

final class EnvFileCopier {

    struct Result {
        let copiedFiles: [String]
        let errors: [String]
    }

    /// Finds .env files recursively in the repository and copies them to the new worktree.
    /// Only copies files that don't already exist in the destination.
    func copyEnvFiles(from repositoryPath: String, to worktreePath: String) -> Result {
        let fileManager = FileManager.default
        var copiedFiles: [String] = []
        var errors: [String] = []

        let envFiles = findEnvFiles(in: repositoryPath)

        for relativePath in envFiles {
            let sourcePath = (repositoryPath as NSString).appendingPathComponent(relativePath)
            let destPath = (worktreePath as NSString).appendingPathComponent(relativePath)

            // Skip if already exists
            guard !fileManager.fileExists(atPath: destPath) else { continue }

            // Ensure parent directory exists
            let destDir = (destPath as NSString).deletingLastPathComponent
            do {
                try fileManager.createDirectory(atPath: destDir, withIntermediateDirectories: true)
                try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
                copiedFiles.append(relativePath)
            } catch {
                errors.append("\(relativePath): \(error.localizedDescription)")
            }
        }

        return Result(copiedFiles: copiedFiles, errors: errors)
    }

    /// Scans for .env* files recursively in the repository directory.
    private func findEnvFiles(in directoryPath: String) -> [String] {
        let fileManager = FileManager.default
        var envFiles: [String] = []

        let excludedDirs: Set<String> = [
            "node_modules", ".git", ".omc", ".claude",
            "dist", "build", ".next", ".nuxt", ".output",
        ]

        guard let enumerator = fileManager.enumerator(atPath: directoryPath) else {
            return []
        }

        while let relativePath = enumerator.nextObject() as? String {
            let fileName = (relativePath as NSString).lastPathComponent

            // Skip excluded directories
            if excludedDirs.contains(fileName) {
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
