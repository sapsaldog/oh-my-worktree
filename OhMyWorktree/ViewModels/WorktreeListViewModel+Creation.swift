import Foundation

// Worktree creation, base-branch listing, toolbar search filtering, and detail
// loading. Split out of WorktreeListViewModel to keep that file within length limits.
extension WorktreeListViewModel {

    /// Worktrees matching `searchText` (name / folder / branch, case-insensitive).
    /// Returns all worktrees when the query is empty.
    var filteredWorktrees: [Worktree] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return worktrees }
        return worktrees.filter { worktree in
            let haystack = "\(worktree.displayName) \(worktree.folderName) \(worktree.branch ?? "")"
            return haystack.lowercased().contains(query)
        }
    }

    /// Creates a worktree. `name` becomes the folder/branch (random when nil/blank);
    /// `copyFiles` overrides the per-repo/global `.worktreeinclude` copy setting when non-nil.
    func addWorktree(name: String? = nil, baseBranch: String? = nil, copyFiles: Bool? = nil) async {
        guard let repository else {
            errorMessage = OhMyWorktreeError.repositoryNotFound.errorDescription
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let existingNames = Set(worktrees.map { $0.folderName })
            let trimmed = name?.trimmingCharacters(in: .whitespaces)
            let folderName = (trimmed?.isEmpty == false ? trimmed : nil)
                ?? RandomNameGenerator.generate(existingFolderNames: existingNames)

            let newWorktree = try await worktreeManager.addWorktree(
                repositoryPath: repository.path,
                folderName: folderName,
                baseBranch: baseBranch
            )

            let metadata = WorktreeMetadata(folderName: folderName)
            await store.addWorktreeMetadata(metadata, repositoryID: repository.id)

            let shouldCopy: Bool
            if let copyFiles {
                shouldCopy = copyFiles
            } else {
                shouldCopy = await shouldCopyFiles(for: repository.id)
            }
            if shouldCopy {
                let copyResult = fileCopier.copyFiles(from: repository.path, to: newWorktree.path)
                if !copyResult.errors.isEmpty {
                    errorMessage = "Some files could not be copied: \(copyResult.errors.joined(separator: ", "))"
                }
            }

            await loadWorktrees()
            selectedWorktree = worktrees.first { $0.path == newWorktree.path }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Branch names available as a base for a new worktree (best-effort; empty on failure).
    func availableBranches() async -> [String] {
        guard let repository else { return [] }
        return (try? await worktreeManager.listBranches(repositoryPath: repository.path)) ?? []
    }

    /// Loads ahead/behind, diff stat, and recent commits for the given worktree.
    /// Drive from a SwiftUI `.task(id:)` so it cancels and reloads on reselection.
    func loadDetail(for worktree: Worktree?) async {
        guard let worktree, let repository else {
            selectedWorktreeDetail = nil
            return
        }
        selectedWorktreeDetail = nil
        var detail = await worktreeManager.worktreeDetail(
            worktreePath: worktree.path,
            repositoryPath: repository.path
        )
        let copier = fileCopier
        let path = worktree.path
        let matches = await Task.detached { copier.includedFiles(in: path) }.value
        // Only files Git ignores were actually copied; committed templates
        // (e.g. .env.example) come with the checkout and don't count.
        detail.copiedFiles = await worktreeManager.gitIgnoredFiles(matches, worktreePath: path)
        guard !Task.isCancelled else { return }
        selectedWorktreeDetail = detail
    }
}
