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

/// Thread-safe byte accumulator for a pipe. The stdout and stderr
/// `readabilityHandler` callbacks fire on independent dispatch queues, so the
/// buffer is guarded by a lock.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var collected: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
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

        // CRITICAL: this executor must never block a libdispatch worker thread.
        // The previous implementation dispatched a worker onto the global pool and
        // blocked it on `DispatchGroup.wait()` while waiting for two more pooled
        // reader blocks — so 64+ concurrent calls parked every thread in the
        // 64-thread global pool, and the reader blocks they waited on could never
        // be scheduled. That deadlock froze "Loading worktrees…" forever. `run`
        // (below) drains the pipes incrementally and resumes via
        // `DispatchGroup.notify`, never `.wait()`, so the pool can't be exhausted.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Self.run(process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe, resuming: continuation)
            }
        } onCancel: {
            // Guard against terminating a process that hasn't started yet,
            // which would raise an Objective-C exception.
            if process.isRunning {
                process.terminate()
            }
        }
    }

    /// Spawns `process`, draining both pipes incrementally via `readabilityHandler`
    /// (so output larger than the ~64KB pipe buffer can't stall the child) and
    /// resuming `continuation` exactly once through `DispatchGroup.notify`. No
    /// pooled thread is ever parked, so concurrent calls cannot exhaust the
    /// libdispatch global pool.
    private static func run(
        _ process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        resuming continuation: CheckedContinuation<CommandResult, Error>
    ) {
        let stdoutBuffer = OutputBuffer()
        let stderrBuffer = OutputBuffer()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        // Three events must complete before resuming: stdout EOF, stderr EOF, and
        // process termination. Each signals a single `leave()`; `notify` fires
        // once, after all three.
        let group = DispatchGroup()
        group.enter()
        group.enter()
        group.enter()

        stdoutHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                group.leave()
            } else {
                stdoutBuffer.append(chunk)
            }
        }
        stderrHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                group.leave()
            } else {
                stderrBuffer.append(chunk)
            }
        }
        process.terminationHandler = { _ in
            group.leave()
        }

        group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
            continuation.resume(returning: CommandResult(
                stdout: String(data: stdoutBuffer.collected, encoding: .utf8) ?? "",
                stderr: String(data: stderrBuffer.collected, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus
            ))
        }

        do {
            try process.run()
        } catch {
            // The process never started, so no handler fires and the group never
            // balances (its `notify` therefore never runs, so there is no
            // double-resume). Detach the handlers and fail the call.
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            process.terminationHandler = nil
            continuation.resume(throwing: error)
        }
    }
}
