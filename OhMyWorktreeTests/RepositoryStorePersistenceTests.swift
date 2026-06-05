import Foundation
import Testing

@testable import OhMyWorktree

/// Exercises `RepositoryStore`'s persistence + CRUD against a temp directory so
/// the write/read round-trips, the backup-aware loader, and the atomic-write
/// error path are covered deterministically (no real Application Support).
@Suite
final class RepositoryStorePersistenceTests {

    // Unique temp directory per test instance; removed in deinit.
    private let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omw-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore() -> RepositoryStore {
        RepositoryStore(storageDirectory: dir)
    }

    private func iso8601Encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: - init creates missing storage directory

    @Test func init_createsStorageDirectoryWhenMissing() async {
        // A nested, not-yet-existing path forces init's createDirectory branch.
        let nested = dir.appendingPathComponent("nested/storage", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: nested.path))

        let store = RepositoryStore(storageDirectory: nested)

        #expect(FileManager.default.fileExists(atPath: nested.path))
        // The instance is usable.
        #expect(await store.getRepositories().isEmpty)
    }

    // MARK: - addWorktreeMetadata duplicate handling

    @Test func addWorktreeMetadata_duplicateFolder_isIgnored() async {
        let store = makeStore()
        let repoID = UUID()
        let folder = "dup-\(UUID().uuidString.prefix(8))"

        await store.addWorktreeMetadata(WorktreeMetadata(folderName: String(folder)), repositoryID: repoID)
        // Second add with the SAME folder evaluates the contains-predicate against
        // an existing element and takes the guard's `else { return }` branch.
        await store.addWorktreeMetadata(
            WorktreeMetadata(folderName: String(folder), customName: "Ignored"),
            repositoryID: repoID
        )

        let metadata = await store.getWorktreeMetadata(repositoryID: repoID)
        #expect(metadata.count == 1)
        #expect(metadata.first?.customName == nil)
    }

    @Test func addWorktreeMetadata_distinctFolders_bothStored() async {
        let store = makeStore()
        let repoID = UUID()
        let a = "a-\(UUID().uuidString.prefix(8))"
        let b = "b-\(UUID().uuidString.prefix(8))"

        await store.addWorktreeMetadata(WorktreeMetadata(folderName: String(a)), repositoryID: repoID)
        // Distinct folder: the contains-predicate runs against the existing entry
        // and returns false, so the append proceeds.
        await store.addWorktreeMetadata(WorktreeMetadata(folderName: String(b)), repositoryID: repoID)

        let metadata = await store.getWorktreeMetadata(repositoryID: repoID)
        #expect(metadata.count == 2)
    }

    // MARK: - Repository CRUD round-trips

    @Test func addAndGetRepository_roundTrips() async {
        let store = makeStore()
        let repo = Repository(name: "Repo", path: "/tmp/repo-\(UUID().uuidString)")

        await store.addRepository(repo)

        let fetched = await store.getRepository(id: repo.id)
        #expect(fetched?.id == repo.id)
        #expect(fetched?.name == "Repo")
    }

    @Test func getRepository_unknownID_returnsNil() async {
        let store = makeStore()
        let result = await store.getRepository(id: UUID())
        #expect(result == nil)
    }

    @Test func updateRepository_existing_updatesAndPersists() async throws {
        let store = makeStore()
        var repo = Repository(name: "Old", path: "/tmp/upd-\(UUID().uuidString)")
        await store.addRepository(repo)

        repo.name = "New"
        await store.updateRepository(repo)

        let fetched = await store.getRepository(id: repo.id)
        #expect(fetched?.name == "New")

        // Persisted to disk: a fresh store reading the same dir sees the update.
        let reloaded = makeStore()
        let reloadedRepo = await reloaded.getRepository(id: repo.id)
        #expect(reloadedRepo?.name == "New")
    }

    @Test func updateRepository_unknownID_doesNothing() async {
        let store = makeStore()
        let ghost = Repository(name: "Ghost", path: "/tmp/ghost-\(UUID().uuidString)")

        await store.updateRepository(ghost)

        let all = await store.getRepositories()
        #expect(all.isEmpty)
    }

    @Test func updateLastAccessed_unknownID_doesNothing() async {
        let store = makeStore()
        await store.updateLastAccessed(id: UUID())
        let all = await store.getRepositories()
        #expect(all.isEmpty)
    }

    // MARK: - updateLastActivity

    @Test func updateLastActivity_existingFolder_bumpsTimestamp() async throws {
        let store = makeStore()
        let repoID = UUID()
        let folder = "feature-\(UUID().uuidString.prefix(8))"
        let original = WorktreeMetadata(
            folderName: String(folder),
            lastActivityAt: Date(timeIntervalSince1970: 0)
        )
        await store.addWorktreeMetadata(original, repositoryID: repoID)

        await store.updateLastActivity(folderName: String(folder), repositoryID: repoID)

        let metadata = await store.getWorktreeMetadata(repositoryID: repoID)
        let found = try #require(metadata.first { $0.folderName == String(folder) })
        #expect(found.lastActivityAt > Date(timeIntervalSince1970: 1))
    }

    @Test func updateLastActivity_newFolder_createsMetadata() async throws {
        let store = makeStore()
        let repoID = UUID()
        let folder = "fresh-\(UUID().uuidString.prefix(8))"

        await store.updateLastActivity(folderName: String(folder), repositoryID: repoID)

        let metadata = await store.getWorktreeMetadata(repositoryID: repoID)
        #expect(metadata.contains { $0.folderName == String(folder) })
    }

    // MARK: - Env copy overrides

    @Test func envCopyOverride_setGetRemove_roundTrips() async {
        let store = makeStore()
        let repoID = UUID()

        #expect(await store.getEnvCopyOverride(for: repoID) == nil)

        await store.setEnvCopyOverride(repositoryID: repoID, enabled: true)
        #expect(await store.getEnvCopyOverride(for: repoID) == true)

        await store.setEnvCopyOverride(repositoryID: repoID, enabled: false)
        #expect(await store.getEnvCopyOverride(for: repoID) == false)

        await store.removeEnvCopyOverride(repositoryID: repoID)
        #expect(await store.getEnvCopyOverride(for: repoID) == nil)
    }

    @Test func envCopyOverride_persistsAcrossReload() async {
        let store = makeStore()
        let repoID = UUID()

        await store.setEnvCopyOverride(repositoryID: repoID, enabled: true)

        // A fresh store reading the same dir must decode the override file,
        // exercising the init's UUID-keyed override loading branch.
        let reloaded = makeStore()
        #expect(await reloaded.getEnvCopyOverride(for: repoID) == true)
    }

    // MARK: - Worktree metadata persistence + reload

    @Test func worktreeMetadata_persistsAcrossReload() async throws {
        let store = makeStore()
        let repoID = UUID()
        let folder = "persist-\(UUID().uuidString.prefix(8))"
        await store.addWorktreeMetadata(
            WorktreeMetadata(folderName: String(folder), customName: "Pretty"),
            repositoryID: repoID
        )

        // Fresh store decodes worktree_metadata.json, exercising the init's
        // UUID-keyed metadata loading branch.
        let reloaded = makeStore()
        let metadata = await reloaded.getWorktreeMetadata(repositoryID: repoID)
        let found = try #require(metadata.first { $0.folderName == String(folder) })
        #expect(found.customName == "Pretty")
    }

    // MARK: - atomicWrite: replace-existing-file branch

    @Test func saveToDisk_overwriteExistingFile_takesReplaceBranch() async {
        let store = makeStore()
        let repo = Repository(name: "First", path: "/tmp/bk-\(UUID().uuidString)")
        await store.addRepository(repo)

        let primary = dir.appendingPathComponent("repositories.json")
        #expect(FileManager.default.fileExists(atPath: primary.path))

        // The second write finds repositories.json already present, so atomicWrite
        // takes the `replaceItemAt` branch (not the first-write moveItem branch).
        var updated = repo
        updated.name = "Second"
        await store.updateRepository(updated)

        #expect(FileManager.default.fileExists(atPath: primary.path))

        // Reloading proves the replace persisted the new contents.
        let reloaded = makeStore()
        #expect(await reloaded.getRepository(id: repo.id)?.name == "Second")
    }

    // MARK: - atomicWrite: failure path (catch + logger)

    @Test func saveToDisk_whenStorageDirectoryMissing_writeFails() async {
        let store = makeStore()

        // Delete the storage directory out from under the store so the temp-file
        // write inside atomicWrite throws, hitting the catch + logger.error path.
        try? FileManager.default.removeItem(at: dir)

        // setEnvCopyOverride marks dirty + calls saveToDisk -> atomicWrite -> throws.
        let repoID = UUID()
        await store.setEnvCopyOverride(repositoryID: repoID, enabled: true)

        // In-memory state is still updated even though the disk write failed.
        #expect(await store.getEnvCopyOverride(for: repoID) == true)

        // No file was produced because the directory does not exist.
        let overridesFile = dir.appendingPathComponent("env_copy_overrides.json")
        #expect(!FileManager.default.fileExists(atPath: overridesFile.path))
    }

    // MARK: - loadJSON branches via init

    @Test func loadJSON_missingFiles_yieldsEmptyState() async {
        // Empty temp dir: all three files are absent, loadJSON returns nil for each.
        let store = makeStore()
        #expect(await store.getRepositories().isEmpty)
        #expect(await store.getWorktreeMetadata(repositoryID: UUID()).isEmpty)
        #expect(await store.getEnvCopyOverride(for: UUID()) == nil)
    }

    @Test func loadJSON_validPrimaryFile_loadsRepositories() async throws {
        let repo = Repository(name: "Loaded", path: "/tmp/loaded-\(UUID().uuidString)")
        let data = try iso8601Encoder().encode([repo])
        try data.write(to: dir.appendingPathComponent("repositories.json"))

        let store = makeStore()

        let fetched = await store.getRepository(id: repo.id)
        #expect(fetched?.name == "Loaded")
    }

    @Test func loadJSON_corruptPrimary_fallsBackToBackup() async throws {
        let repo = Repository(name: "FromBackup", path: "/tmp/backup-\(UUID().uuidString)")

        // Primary is corrupt; backup is valid. loadJSON must fall through to the
        // .backup branch and decode it.
        try Data("not json".utf8).write(to: dir.appendingPathComponent("repositories.json"))
        let backupData = try iso8601Encoder().encode([repo])
        try backupData.write(to: dir.appendingPathComponent("repositories.json.backup"))

        let store = makeStore()

        let all = await store.getRepositories()
        #expect(all.count == 1)
        #expect(all.first?.name == "FromBackup")
    }

    @Test func loadJSON_corruptPrimaryAndBackup_yieldsEmpty() async throws {
        // Both primary and backup are unreadable JSON: loadJSON returns nil and
        // the store starts empty (the final `return nil` branch).
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("repositories.json"))
        try Data("also garbage".utf8).write(to: dir.appendingPathComponent("repositories.json.backup"))

        let store = makeStore()

        #expect(await store.getRepositories().isEmpty)
    }
}
