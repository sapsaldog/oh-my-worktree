import Foundation

// MARK: - Quick Remove Worktree (via queue)

extension WorktreeListViewModel {

    func quickRemoveWorktree(_ worktree: Worktree) {
        guard let repository else { return }
        let job = BackgroundJob(
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            folderName: worktree.folderName,
            displayName: worktree.displayName,
            repositoryPath: repository.path,
            repositoryID: repository.id,
            kind: .quickRemove
        )
        jobQueue.enqueue(job)
    }

    func quickRemoveSelectedWorktrees() {
        guard let repository else { return }
        let targets = worktrees.filter { worktree in
            selectedWorktreeIDs.contains(worktree.id)
                && !worktree.isRoot(of: repository)
                && !worktree.isBare
                && !worktree.isLocked
                && !jobQueue.busyWorktreeIDs.contains(worktree.id)
        }
        let jobs = targets.map { worktree in
            BackgroundJob(
                worktreeID: worktree.id,
                worktreePath: worktree.path,
                folderName: worktree.folderName,
                displayName: worktree.displayName,
                repositoryPath: repository.path,
                repositoryID: repository.id,
                kind: .quickRemove
            )
        }
        jobQueue.enqueue(jobs)
        selectedWorktreeIDs = []
    }
}
