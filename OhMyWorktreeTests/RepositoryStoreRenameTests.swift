import XCTest

@testable import OhMyWorktree

final class RepositoryStoreRenameTests: XCTestCase {

    // Each test gets a unique repository ID to prevent cross-test interference
    private var testRepoID: UUID!
    private let store = RepositoryStore.shared
    private let testFolderName = "test-worktree-rename-\(UUID().uuidString.prefix(8))"

    override func setUp() async throws {
        try await super.setUp()
        testRepoID = UUID()
        // Ensure clean state before each test
        await store.removeWorktreeMetadata(folderName: testFolderName, repositoryID: testRepoID)
    }

    override func tearDown() async throws {
        // Clean up test data after each test
        await store.removeWorktreeMetadata(folderName: testFolderName, repositoryID: testRepoID)
        try await super.tearDown()
    }

    // MARK: - updateCustomName

    func testUpdateCustomName_setsCustomName() async {
        // Given: metadata exists without customName
        let metadata = WorktreeMetadata(folderName: testFolderName)
        await store.addWorktreeMetadata(metadata, repositoryID: testRepoID)

        // When: update customName
        await store.updateCustomName(folderName: testFolderName, customName: "My Feature", repositoryID: testRepoID)

        // Then: customName is persisted
        let result = await store.getWorktreeMetadata(repositoryID: testRepoID)
        let found = result.first(where: { $0.folderName == self.testFolderName })
        XCTAssertEqual(found?.customName, "My Feature")
    }

    func testUpdateCustomName_clearsCustomName_withNil() async {
        // Given: metadata has a customName
        let metadata = WorktreeMetadata(folderName: testFolderName, customName: "My Feature")
        await store.addWorktreeMetadata(metadata, repositoryID: testRepoID)

        // When: set customName to nil
        await store.updateCustomName(folderName: testFolderName, customName: nil, repositoryID: testRepoID)

        // Then: customName is cleared
        let result = await store.getWorktreeMetadata(repositoryID: testRepoID)
        let found = result.first(where: { $0.folderName == self.testFolderName })
        XCTAssertNil(found?.customName)
    }

    func testUpdateCustomName_sanitizesWhitespaceOnlyToNil() async {
        // Given: metadata exists
        let metadata = WorktreeMetadata(folderName: testFolderName)
        await store.addWorktreeMetadata(metadata, repositoryID: testRepoID)

        // When: set customName to whitespace-only
        await store.updateCustomName(folderName: testFolderName, customName: "   ", repositoryID: testRepoID)

        // Then: customName is sanitized to nil
        let result = await store.getWorktreeMetadata(repositoryID: testRepoID)
        let found = result.first(where: { $0.folderName == self.testFolderName })
        XCTAssertNil(found?.customName)
    }

    func testUpdateCustomName_trimsWhitespace() async {
        // Given: metadata exists
        let metadata = WorktreeMetadata(folderName: testFolderName)
        await store.addWorktreeMetadata(metadata, repositoryID: testRepoID)

        // When: set customName with leading/trailing whitespace
        await store.updateCustomName(folderName: testFolderName, customName: "  My Feature  ", repositoryID: testRepoID)

        // Then: customName is trimmed
        let result = await store.getWorktreeMetadata(repositoryID: testRepoID)
        let found = result.first(where: { $0.folderName == self.testFolderName })
        XCTAssertEqual(found?.customName, "My Feature")
    }

    func testUpdateCustomName_nonExistentFolder_doesNothing() async {
        // When: update customName for non-existent folder
        await store.updateCustomName(folderName: "nonexistent-\(testRepoID!.uuidString)", customName: "Name", repositoryID: testRepoID)

        // Then: no metadata created
        let result = await store.getWorktreeMetadata(repositoryID: testRepoID)
        XCTAssertTrue(result.isEmpty)
    }
}
