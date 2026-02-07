import Foundation

/// Monitors a worktree's git HEAD file for branch changes using DispatchSource.
/// All methods must be called from the main thread.
final class GitHeadMonitor {

    // MARK: - Properties

    private var source: DispatchSourceFileSystemObject?
    private var monitoredWorktreePath: String?
    private var pendingRestart: DispatchWorkItem?
    var onBranchChange: ((String?) -> Void)?

    // MARK: - Lifecycle

    deinit {
        // DispatchSource.cancel() is thread-safe, so deinit is safe on any thread.
        // The cancel handler (dispatched on .main) closes the fd.
        source?.cancel()
        pendingRestart?.cancel()
    }

    // MARK: - Public

    func startMonitoring(worktreePath: String) {
        stopMonitoring()
        monitoredWorktreePath = worktreePath

        guard let headPath = resolveHeadPath(worktreePath: worktreePath) else { return }

        let fd = open(headPath, O_EVTONLY)
        guard fd >= 0 else { return }

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
        pendingRestart?.cancel()
        pendingRestart = nil
        source?.cancel()
        source = nil
        monitoredWorktreePath = nil
    }

    // MARK: - Private

    private func scheduleRestart() {
        pendingRestart?.cancel()
        guard let path = monitoredWorktreePath else { return }

        let work = DispatchWorkItem { [weak self] in
            self?.startMonitoring(worktreePath: path)
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
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
