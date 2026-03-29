import Foundation

// MARK: - Worktree List Parsing

extension WorktreeManager {

    func parseWorktreeList(_ output: String) -> [Worktree] {
        output.components(separatedBy: "\n\n").compactMap { parseWorktreeBlock($0) }
    }

    private func parseWorktreeBlock(_ block: String) -> Worktree? {
        let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBlock.isEmpty else { return nil }

        let lines = trimmedBlock.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let parsed = parseWorktreeLines(lines)

        // Prunable entries have no directory on disk; exclude them so stale
        // worktrees don't reappear in the list after manual deletion.
        guard !parsed.isPrunable else { return nil }
        guard let worktreePath = parsed.path else { return nil }
        return Worktree(
            path: worktreePath,
            folderName: (worktreePath as NSString).lastPathComponent,
            branch: parsed.branch,
            commitHash: parsed.commitHash,
            isDetached: parsed.isDetached,
            isBare: parsed.isBare,
            isLocked: parsed.isLocked
        )
    }

    private func parseWorktreeLines(_ lines: [String]) -> WorktreeLineTokens {
        var path: String?
        var commitHash = ""
        var branch: String?
        var isDetached = false
        var isBare = false
        var isLocked = false
        var isPrunable = false

        for lineStr in lines {
            if lineStr.hasPrefix("worktree ") {
                path = String(lineStr.dropFirst("worktree ".count))
            } else if lineStr.hasPrefix("HEAD ") {
                commitHash = String(lineStr.dropFirst("HEAD ".count))
            } else if lineStr.hasPrefix("branch ") {
                let refPath = String(lineStr.dropFirst("branch ".count))
                branch = refPath.hasPrefix("refs/heads/")
                    ? String(refPath.dropFirst("refs/heads/".count))
                    : refPath
            } else if lineStr == "detached" {
                isDetached = true
            } else if lineStr == "bare" {
                isBare = true
            } else if lineStr.hasPrefix("locked") {
                isLocked = true
            } else if lineStr.hasPrefix("prunable") {
                isPrunable = true
            }
        }

        return WorktreeLineTokens(
            path: path, commitHash: commitHash, branch: branch,
            isDetached: isDetached, isBare: isBare, isLocked: isLocked,
            isPrunable: isPrunable
        )
    }
}

private struct WorktreeLineTokens {
    let path: String?
    let commitHash: String
    let branch: String?
    let isDetached: Bool
    let isBare: Bool
    let isLocked: Bool
    let isPrunable: Bool
}
