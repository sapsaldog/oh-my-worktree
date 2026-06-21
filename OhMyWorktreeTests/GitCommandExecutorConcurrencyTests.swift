import Foundation
import Testing

@testable import OhMyWorktree

/// Behavioral tests for the real `GitCommandExecutor` (process spawning + pipe
/// draining). The executor is otherwise mocked everywhere; these lock in the
/// contract the mock stands in for — most importantly that it never deadlocks
/// the libdispatch global thread pool under high concurrency.
@Suite("GitCommandExecutor concurrency", .serialized)
struct GitCommandExecutorConcurrencyTests {

    /// Regression for the "Loading worktrees…" freeze: the original executor
    /// dispatched each command's blocking pipe-drain + `waitUntilExit` onto the
    /// global pool and then blocked that worker on `DispatchGroup.wait()`. With
    /// 64+ concurrent calls, every one of libdispatch's 64 pool threads sat in
    /// `wait()` waiting for reader blocks that could never be scheduled (no free
    /// thread) — a permanent deadlock. The executor must complete every call no
    /// matter how many run at once.
    @Test("completes all commands when concurrency exceeds the 64-thread dispatch pool",
          .timeLimit(.minutes(1)))
    func highConcurrency_doesNotExhaustDispatchPool() async throws {
        let executor = GitCommandExecutor()
        let concurrentCount = 80   // > libdispatch's 64-thread soft limit

        let completed = try await withThrowingTaskGroup(of: Int32.self) { group in
            for _ in 0..<concurrentCount {
                group.addTask {
                    // `/bin/sleep 0.2` keeps every invocation simultaneously in
                    // flight so the pool is genuinely saturated; it produces no
                    // output, isolating spawn + completion as the thing tested.
                    let result = try await executor.execute(
                        command: "/bin/sleep",
                        arguments: ["0.2"],
                        workingDirectory: nil
                    )
                    return result.exitCode
                }
            }
            var count = 0
            for try await code in group {
                #expect(code == 0)
                count += 1
            }
            return count
        }

        #expect(completed == concurrentCount)
    }

    @Test("captures stdout and a zero exit code")
    func capturesStdoutAndExitCode() async throws {
        let result = try await GitCommandExecutor().execute(
            command: "/bin/echo", arguments: ["hello"], workingDirectory: nil
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "hello\n")
        #expect(result.stderr.isEmpty)
    }

    @Test("reports a non-zero exit code")
    func reportsNonzeroExitCode() async throws {
        let result = try await GitCommandExecutor().execute(
            command: "/bin/sh", arguments: ["-c", "exit 3"], workingDirectory: nil
        )
        #expect(result.exitCode == 3)
    }

    /// Output larger than the OS pipe buffer (~64KB) must drain without
    /// deadlocking — the child blocks on a full pipe until the reader drains it,
    /// so reading has to happen concurrently with the process running.
    @Test("drains output larger than the pipe buffer")
    func drainsLargeOutput() async throws {
        let byteCount = 200_000
        let result = try await GitCommandExecutor().execute(
            command: "/bin/sh",
            arguments: ["-c", "yes x | head -c \(byteCount)"],
            workingDirectory: nil
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.count == byteCount)
    }
}
