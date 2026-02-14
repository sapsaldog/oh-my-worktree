import Foundation

struct CommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

protocol GitCommandExecuting {
    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult
}

/// Executes Git commands via Process. Thread-safe because it has no mutable state.
/// @unchecked Sendable is safe here because all operations are stateless.
final class GitCommandExecutor: GitCommandExecuting, @unchecked Sendable {
    func execute(
        command: String = "/usr/bin/git",
        arguments: [String],
        workingDirectory: String? = nil
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

            process.environment = ProcessInfo.processInfo.environment.merging(
                ["LC_ALL": "C"],
                uniquingKeysWith: { _, new in new }
            )

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let result = CommandResult(
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus
                )
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
