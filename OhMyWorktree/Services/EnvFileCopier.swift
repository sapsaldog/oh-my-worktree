import Foundation

final class EnvFileCopier {

    struct Result {
        let copiedFiles: [String]
        let errors: [String]
    }

    /// Finds .env files in the repository root and copies them to the new worktree.
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

    /// Scans for .env* files in the repository root directory.
    private func findEnvFiles(in directoryPath: String) -> [String] {
        let fileManager = FileManager.default
        var envFiles: [String] = []

        // Check root directory for .env files
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directoryPath) else {
            return []
        }

        for name in contents where name.hasPrefix(".env") {
            let fullPath = (directoryPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                envFiles.append(name)
            }
        }

        return envFiles.sorted()
    }
}
