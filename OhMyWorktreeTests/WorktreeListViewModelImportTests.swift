import Combine
import Foundation
import Testing

@testable import OhMyWorktree

// MARK: - addWorktreeFromPR queue-collision guard

extension WorktreeListViewModelTests {

    /// Enqueueing the same PR twice before the first job completes must produce
    /// distinct folderNames and localBranches (Fix #3).
    @Test func addWorktreeFromPR_duplicateEnqueue_secondJobUsesVersionedName() {
        sut.worktrees = [rootWorktree]

        let pr = PullRequestInfo(
            number: 10,
            url: URL(string: "https://github.com/user/repo/pull/10")!,
            branch: "feature/new",
            state: .open
        )

        sut.addWorktreeFromPR(pr)
        // First job is pending — worktrees list hasn't updated yet.
        #expect(sut.jobQueue.jobs.count == 1)

        sut.addWorktreeFromPR(pr)
        #expect(sut.jobQueue.jobs.count == 2)

        let job1 = sut.jobQueue.jobs[0]
        let job2 = sut.jobQueue.jobs[1]
        #expect(job1.folderName != job2.folderName,
               "Second import must use a different random folder name")
        // Folder names are random; verify they are non-empty and distinct.
        #expect(!job1.folderName.isEmpty)
        #expect(!job2.folderName.isEmpty)
        guard case .addWorktreeFromPR(_, let local2, _) = job2.kind else {
            Issue.record("Expected addWorktreeFromPR kind"); return
        }
        #expect(local2 == "feature/new-v2")
    }
}

// MARK: - renameWorktree selectedWorktreeSubject

extension WorktreeListViewModelTests {

    /// Renaming a selected worktree must emit selectedWorktreeSubject so the
    /// AppDelegate can update the menu bar title immediately (Fix #4).
    @Test func renameWorktree_selectedWorktreeSubjectEmitsUpdatedCustomName() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        await sut.loadWorktrees()
        let worktree = sut.worktrees.first(where: { $0.folderName == "feature-a" })!
        sut.selectedWorktree = worktree

        var received: [Worktree?] = []
        let cancellable = sut.selectedWorktreeSubject.sink { received.append($0) }
        defer { cancellable.cancel() }

        await sut.renameWorktree(worktree, newName: "My Feature")

        #expect(!received.isEmpty,
               "selectedWorktreeSubject must emit after rename")
        #expect(received.last??.customName == "My Feature")
    }

    /// Renaming a worktree that is NOT currently selected must not emit the subject.
    @Test func renameWorktree_nonSelected_doesNotEmitSubject() async {
        mockExecutor.stubWorktrees("""
        worktree /tmp/test-repo
        HEAD abc1111
        branch refs/heads/main

        worktree /tmp/worktrees/feature-a
        HEAD abc2222
        branch refs/heads/feature/a

        """)

        await sut.loadWorktrees()
        let worktree = sut.worktrees.first(where: { $0.folderName == "feature-a" })!
        // Leave selectedWorktree as nil

        var received: [Worktree?] = []
        let cancellable = sut.selectedWorktreeSubject.sink { received.append($0) }
        defer { cancellable.cancel() }

        await sut.renameWorktree(worktree, newName: "Other")

        #expect(received.isEmpty,
               "selectedWorktreeSubject must not emit when renamed worktree is not selected")
    }
}
