import Foundation

// MARK: - Worktree detail queries (ahead/behind, diff stat, recent commits)
//
// All queries are best-effort: a failure yields the empty/nil shape so the detail
// pane degrades gracefully and never surfaces an error. Pure parsers are factored
// out as static functions so they can be unit-tested without a process.

extension WorktreeManager {

    /// Loads everything the detail pane needs beyond the worktree's own fields.
    func worktreeDetail(worktreePath: String, repositoryPath: String) async -> WorktreeDetail {
        let base = await defaultBranch(repositoryPath: repositoryPath)
        async let aheadBehind = aheadBehind(worktreePath: worktreePath)
        async let diff = diffStat(worktreePath: worktreePath, baseBranch: base)
        async let commits = recentCommits(worktreePath: worktreePath)
        return await WorktreeDetail(aheadBehind: aheadBehind, diff: diff, commits: commits)
    }

    // MARK: Ahead / Behind

    /// `git rev-list --left-right --count @{upstream}...HEAD` → (behind, ahead).
    /// Returns nil when there is no upstream (command fails).
    func aheadBehind(worktreePath: String) async -> AheadBehind? {
        guard let result = try? await executor.execute(
            arguments: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
            workingDirectory: worktreePath
        ), result.exitCode == 0 else { return nil }
        return Self.parseAheadBehind(result.stdout)
    }

    static func parseAheadBehind(_ output: String) -> AheadBehind? {
        let parts = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "\t" || $0 == " " })
        guard parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) else { return nil }
        return AheadBehind(ahead: ahead, behind: behind)
    }

    // MARK: Default branch

    /// Resolves the repo's default branch from `origin/HEAD`, falling back to `main`.
    func defaultBranch(repositoryPath: String) async -> String {
        if let result = try? await executor.execute(
            arguments: ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
            workingDirectory: repositoryPath
        ), result.exitCode == 0 {
            let ref = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let slash = ref.lastIndex(of: "/") {
                let name = String(ref[ref.index(after: slash)...])
                if !name.isEmpty { return name }
            } else if !ref.isEmpty {
                return ref
            }
        }
        return "main"
    }

    // MARK: Diff stat

    /// `git diff --numstat <merge-base>...HEAD` summed across files.
    func diffStat(worktreePath: String, baseBranch: String) async -> DiffStat {
        let base = await mergeBase(worktreePath: worktreePath, baseBranch: baseBranch)
        guard !base.isEmpty,
              let result = try? await executor.execute(
                arguments: ["diff", "--numstat", "\(base)...HEAD"],
                workingDirectory: worktreePath
              ), result.exitCode == 0 else {
            return DiffStat(added: 0, removed: 0, files: 0)
        }
        return Self.parseDiffStat(result.stdout)
    }

    private func mergeBase(worktreePath: String, baseBranch: String) async -> String {
        if let result = try? await executor.execute(
            arguments: ["merge-base", "HEAD", baseBranch],
            workingDirectory: worktreePath
        ), result.exitCode == 0 {
            let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return baseBranch
    }

    static func parseDiffStat(_ output: String) -> DiffStat {
        var added = 0
        var removed = 0
        var files = 0
        for line in output.split(separator: "\n") {
            let columns = line.split(separator: "\t")
            guard columns.count >= 3 else { continue }
            files += 1
            if let value = Int(columns[0]) { added += value }    // "-" for binary → skipped
            if let value = Int(columns[1]) { removed += value }
        }
        return DiffStat(added: added, removed: removed, files: files)
    }

    // MARK: Recent commits

    /// `git log -n <limit>` with unit-separated fields (hash, subject, author, ts).
    func recentCommits(worktreePath: String, limit: Int = 5) async -> [Commit] {
        guard let result = try? await executor.execute(
            arguments: ["log", "-n", "\(limit)", "--format=%h%x1f%s%x1f%an%x1f%ct"],
            workingDirectory: worktreePath
        ), result.exitCode == 0 else { return [] }
        return Self.parseCommits(result.stdout)
    }

    static func parseCommits(_ output: String) -> [Commit] {
        let separator = "\u{1f}"
        return output.split(separator: "\n").compactMap { line -> Commit? in
            let fields = line.components(separatedBy: separator)
            guard fields.count == 4 else { return nil }
            let date = TimeInterval(fields[3]).map { Date(timeIntervalSince1970: $0) }
            return Commit(hash: fields[0], message: fields[1], author: fields[2], date: date)
        }
    }
}
