import Foundation
import os

private let logger = Logger(subsystem: "com.ohmyworktree", category: "GitHeadMonitor")

/// Monitors a worktree's git HEAD file for branch changes using DispatchSource.
/// All methods must be called from the main thread.
final class GitHeadMonitor {

    // MARK: - Properties

    private var source: DispatchSourceFileSystemObject?
    private var monitoredWorktreePath: String?
    private var pendingRestart: DispatchWorkItem?
    var onBranchChange: ((String?) -> Void)?

    /// Maximum delay used by the retry backoff. The first failure schedules a 0.1s
    /// retry; subsequent failures double up to this ceiling so we don't busy-loop
    /// when a worktree is briefly missing (e.g. mid-rebase or mid-prune).
    private static let maxRestartDelay: TimeInterval = 2.0
    private var consecutiveFailures = 0

    // MARK: - Lifecycle

    deinit {
        // DispatchSource.cancel() is thread-safe, so deinit is safe on any thread.
        // The cancel handler (dispatched on .main) closes the fd.
        source?.cancel()
        pendingRestart?.cancel()
    }

    // MARK: - Public

    func startMonitoring(worktreePath: String) {
        stopMonitoring(resetFailures: false)
        monitoredWorktreePath = worktreePath

        guard let headPath = resolveHeadPath(worktreePath: worktreePath) else {
            logger.debug("Could not resolve HEAD for worktree: \(worktreePath, privacy: .public)")
            scheduleRestartWithBackoff()
            return
        }

        let fd = open(headPath, O_EVTONLY)
        guard fd >= 0 else {
            // ENOENT during a git operation is expected and self-heals on retry.
            logger.debug("open(O_EVTONLY) failed for \(headPath, privacy: .public), errno=\(errno)")
            scheduleRestartWithBackoff()
            return
        }

        consecutiveFailures = 0

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let branch = self.readBranchFromHead(at: headPath)
            self.onBranchChange?(branch)

            // When git replaces HEAD via atomic rename, the old inode becomes
            // stale and this source will never fire again. Re-establish monitoring
            // after a short delay to coalesce rapid rename storms (e.g. git rebase).
            if source.data.contains(.delete) || source.data.contains(.rename) {
                self.scheduleRestart()
            }
        }

        // Capture fd directly so the cancel handler always closes the correct
        // file descriptor, even if startMonitoring is called again before this runs.
        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.source = source
    }

    func stopMonitoring() {
        stopMonitoring(resetFailures: true)
    }

    // MARK: - Private

    private func stopMonitoring(resetFailures: Bool) {
        pendingRestart?.cancel()
        pendingRestart = nil
        source?.cancel()
        source = nil
        if resetFailures {
            consecutiveFailures = 0
            monitoredWorktreePath = nil
        }
    }

    private func scheduleRestart() {
        pendingRestart?.cancel()
        guard let path = monitoredWorktreePath else { return }

        let work = DispatchWorkItem { [weak self] in
            self?.startMonitoring(worktreePath: path)
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// Used when initial setup fails (HEAD missing or open() failed). Doubles the
    /// delay each attempt up to `maxRestartDelay` so transient errors during git
    /// operations recover without flooding the dispatch queue.
    private func scheduleRestartWithBackoff() {
        pendingRestart?.cancel()
        guard let path = monitoredWorktreePath else { return }

        consecutiveFailures += 1
        let delay = min(0.1 * pow(2.0, Double(consecutiveFailures - 1)), Self.maxRestartDelay)

        let work = DispatchWorkItem { [weak self] in
            self?.startMonitoring(worktreePath: path)
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func resolveHeadPath(worktreePath: String) -> String? {
        let gitPath = (worktreePath as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory)

        guard exists else { return nil }

        if isDirectory.boolValue {
            // Main worktree: .git is a directory
            return (gitPath as NSString).appendingPathComponent("HEAD")
        } else {
            // Linked worktree: .git is a file containing "gitdir: <path>"
            guard let content = try? String(contentsOfFile: gitPath, encoding: .utf8) else { return nil }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("gitdir: ") else { return nil }

            let gitdir = String(trimmed.dropFirst("gitdir: ".count))
            let resolvedGitdir: String
            if (gitdir as NSString).isAbsolutePath {
                resolvedGitdir = gitdir
            } else {
                resolvedGitdir = (worktreePath as NSString).appendingPathComponent(gitdir)
            }
            return (resolvedGitdir as NSString).appendingPathComponent("HEAD")
        }
    }

    private func readBranchFromHead(at path: String) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Symbolic ref: "ref: refs/heads/<branch>"
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }

        // Detached HEAD (raw commit hash)
        return nil
    }
}
