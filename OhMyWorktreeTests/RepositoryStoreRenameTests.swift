import Foundation
import Testing

@testable import OhMyWorktree

@Suite
final class RepositoryStoreRenameTests {

    private let testRepoID: UUID
    private let store = RepositoryStore.shared
    private let testFolderName = "test-worktree-rename-\(UUID().uuidString.prefix(8))"

    init() async throws {
        testRepoID = UUID()
        await store.removeWorktreeMetadata(folderName: testFolderName, repositoryID: testRepoID)
    }

    deinit {
        let folderName = testFolderName
        let repoID = testRepoID
        let store = self.store
        Task { @MainActor in
            await store.removeWorktreeMetadata(folderName: folderName, repositoryID: repoID)
        }
    }

    @Test func updateCustomName_setsCustomName() async {
        let metadata = WorktreeMetadata(folderName: testFolderName)
        await store.addWorktreeMetadata(metadata, repositoryID: testRepoID)

        await store.updateCustomName(folderName: testFolderName, customName: "My Feature", repositoryID: testRepoID)

        let result = await store.getWorktreeMetadata(repositoryID: testRepoID)
        let found = result.first(where: { $0.folderName == self.testFolderName })
        #expect(found?.customName == "My Feature")
    }

    @Test func updateCustomName_clearsCustomName_withNil() async {
        let metadata = WorktreeMetadata(folderName: testFolderName, customName: "My Feature")
        await store.addWorktreeMetadata(metadata, repositoryID: testRepoID)

        await store.updateCustomName(folderName: testFolderName, customName: nil, repositoryID: testRepoID)

        let result = await store.getWorktreeMetadata(repositoryID: testRepoID)
        let found = result.first(where: { $0.folderName == self.testFolderName })
        #expect(found?.customName == nil)
    }

    @Test func updateCustomName_sanitizesWhitespaceOnlyToNil() async {
        let metadata = WorktreeMetadata(folderName: testFolderName)
        await store.addWorktreeMetadata(metadata, repositoryID: testRepoID)

        await store.updateCustomName(folderName: testFolderName, customName: "   ", repositoryID: testRepoID)

        let result = await store.getWorktreeMetadata(repositoryID: testRepoID)
        let found = result.first(where: { $0.folderName == self.testFolderName })
        #expect(found?.customName == nil)
    }

    @Test func updateCustomName_trimsWhitespace() async {
        let metadata = WorktreeMetadata(folderName: testFolderName)
        await store.addWorktreeMetadata(metadata, repositoryID: testRepoID)

        await store.updateCustomName(folderName: testFolderName, customName: "  My Feature  ", repositoryID: testRepoID)

        let result = await store.getWorktreeMetadata(repositoryID: testRepoID)
        let found = result.first(where: { $0.folderName == self.testFolderName })
        #expect(found?.customName == "My Feature")
    }

    @Test func updateCustomName_nonExistentFolder_doesNothing() async {
        await store.updateCustomName(
            folderName: "nonexistent-\(testRepoID.uuidString)",
            customName: "Name",
            repositoryID: testRepoID
        )

        let result = await store.getWorktreeMetadata(repositoryID: testRepoID)
        #expect(result.isEmpty)
    }
}
