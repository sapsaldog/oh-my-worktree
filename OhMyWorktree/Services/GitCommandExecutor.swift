import Foundation

struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

protocol GitCommandExecuting: Sendable {
    func execute(command: String, arguments: [String], workingDirectory: String?) async throws -> CommandResult
}

extension GitCommandExecuting {
    func execute(arguments: [String], workingDirectory: String?) async throws -> CommandResult {
        try await execute(command: "/usr/bin/git", arguments: arguments, workingDirectory: workingDirectory)
    }
}

/// Executes Git commands via Process. Thread-safe because it has no mutable state.
final class GitCommandExecutor: GitCommandExecuting, Sendable {
    func execute(
        command: String = "/usr/bin/git",
        arguments: [String],
        workingDirectory: String? = nil
    ) async throws -> CommandResult {
        // Create process before entering the continuation so that the
        // withTaskCancellationHandler's onCancel closure can capture and terminate it.
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

        // withTaskCancellationHandler ensures that when the enclosing Task is cancelled
        // (e.g. by BackgroundTaskQueue's timeout), the spawned process receives SIGTERM
        // instead of becoming a zombie that blocks waitUntilExit() indefinitely.
        // The blocking work (run + waitUntilExit) is dispatched to a global queue so it
        // never blocks the calling actor (e.g. MainActor).
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()

                        // Read both pipes concurrently to prevent deadlock.
                        // If either pipe's buffer fills (~64KB on macOS), the child
                        // blocks until it's drained. Sequential reads can deadlock
                        // when one pipe fills while we're blocked reading the other.
                        var stdoutData = Data()
                        var stderrData = Data()
                        let group = DispatchGroup()
                        group.enter()
                        DispatchQueue.global(qos: .userInitiated).async {
                            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                            group.leave()
                        }
                        group.enter()
                        DispatchQueue.global(qos: .userInitiated).async {
                            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                            group.leave()
                        }
                        group.wait()

                        process.waitUntilExit()

                        continuation.resume(returning: CommandResult(
                            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                            stderr: String(data: stderrData, encoding: .utf8) ?? "",
                            exitCode: process.terminationStatus
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            // Guard against terminating a process that hasn't started yet,
            // which would raise an Objective-C exception.
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
