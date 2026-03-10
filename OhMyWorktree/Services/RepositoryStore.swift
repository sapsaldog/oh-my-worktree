import Foundation
import os

actor RepositoryStore {
    static let shared = RepositoryStore()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ohmyworktree",
        category: "RepositoryStore"
    )

    // No default values: init body performs definite initialization, which is
    // allowed in a nonisolated actor init (Swift 6). Default values would make
    // the body assignments "mutations", which are forbidden in that context.
    private var repositories: [Repository]
    private var worktreeMetadata: [UUID: [WorktreeMetadata]] // keyed by repository ID
    private var envCopyOverrides: [UUID: Bool]

    /// Dirty flags — track which data sets were modified since the last save,
    /// so `saveToDisk()` only re-encodes and writes the files that changed.
    private var dirtyRepos: Bool
    private var dirtyMetadata: Bool
    private var dirtyOverrides: Bool

    private nonisolated var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OhMyWorktree", isDirectory: true)
    }

    private nonisolated var repositoriesFileURL: URL {
        storageDirectory.appendingPathComponent("repositories.json")
    }

    private nonisolated var metadataFileURL: URL {
        storageDirectory.appendingPathComponent("worktree_metadata.json")
    }

    private nonisolated var envCopyOverridesFileURL: URL {
        storageDirectory.appendingPathComponent("env_copy_overrides.json")
    }

    // MARK: - Initialization

    private init() {
        // Compute URLs locally — nonisolated computed properties reference `self`,
        // which cannot be used before all stored properties are initialized.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storageDir = appSupport.appendingPathComponent("OhMyWorktree", isDirectory: true)

        if !FileManager.default.fileExists(atPath: storageDir.path) {
            try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Load into locals first, then assign to self in three definite-initialization
        // writes at the end. Swift 6 permits `self.x = value` in a nonisolated actor
        // init only when it is the *first* (definite) assignment to that property.
        let loadedRepos: [Repository] = Self.loadJSON(
            from: storageDir.appendingPathComponent("repositories.json"),
            type: [Repository].self,
            decoder: decoder
        ) ?? []

        var loadedMetadata: [UUID: [WorktreeMetadata]] = [:]
        if let decoded: [String: [WorktreeMetadata]] = Self.loadJSON(
            from: storageDir.appendingPathComponent("worktree_metadata.json"),
            type: [String: [WorktreeMetadata]].self,
            decoder: decoder
        ) {
            for (key, value) in decoded {
                if let uuid = UUID(uuidString: key) { loadedMetadata[uuid] = value }
            }
        }

        var loadedOverrides: [UUID: Bool] = [:]
        if let decoded: [String: Bool] = Self.loadJSON(
            from: storageDir.appendingPathComponent("env_copy_overrides.json"),
            type: [String: Bool].self,
            decoder: decoder
        ) {
            for (key, value) in decoded {
                if let uuid = UUID(uuidString: key) { loadedOverrides[uuid] = value }
            }
        }

        self.repositories = loadedRepos
        self.worktreeMetadata = loadedMetadata
        self.envCopyOverrides = loadedOverrides
        self.dirtyRepos = false
        self.dirtyMetadata = false
        self.dirtyOverrides = false
    }

    // MARK: - Backup-Aware Loading

    private static func loadJSON<T: Decodable>(
        from url: URL,
        type: T.Type,
        decoder: JSONDecoder
    ) -> T? {
        // 1st: try the primary file
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(T.self, from: data) {
            return decoded
        }

        // 2nd: try the .backup file
        let backupURL = url.appendingPathExtension("backup")
        if let data = try? Data(contentsOf: backupURL),
           let decoded = try? decoder.decode(T.self, from: data) {
            return decoded
        }

        // Both failed — return nil (first launch or unrecoverable)
        return nil
    }

    // MARK: - Repository CRUD

    func getRepositories() -> [Repository] {
        return repositories
    }

    func addRepository(_ repository: Repository) {
        guard !repositories.contains(where: { $0.path == repository.path }) else { return }
        repositories.append(repository)
        dirtyRepos = true
        saveToDisk()
    }

    func removeRepository(id: UUID) {
        repositories.removeAll { $0.id == id }
        dirtyRepos = true
        if worktreeMetadata.removeValue(forKey: id) != nil { dirtyMetadata = true }
        if envCopyOverrides.removeValue(forKey: id) != nil { dirtyOverrides = true }
        saveToDisk()
    }

    func updateRepository(_ repository: Repository) {
        guard let index = repositories.firstIndex(where: { $0.id == repository.id }) else { return }
        repositories[index] = repository
        dirtyRepos = true
        saveToDisk()
    }

    func getRepository(id: UUID) -> Repository? {
        return repositories.first { $0.id == id }
    }

    func updateLastAccessed(id: UUID) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        repositories[index].lastAccessedAt = Date()
        dirtyRepos = true
        saveToDisk()
    }

    // MARK: - Worktree Metadata

    func getWorktreeMetadata(repositoryID: UUID) -> [WorktreeMetadata] {
        return worktreeMetadata[repositoryID] ?? []
    }

    func addWorktreeMetadata(_ metadata: WorktreeMetadata, repositoryID: UUID) {
        var existing = worktreeMetadata[repositoryID] ?? []
        guard !existing.contains(where: { $0.folderName == metadata.folderName }) else { return }
        existing.append(metadata)
        worktreeMetadata[repositoryID] = existing
        dirtyMetadata = true
        saveToDisk()
    }

    func removeWorktreeMetadata(folderName: String, repositoryID: UUID) {
        worktreeMetadata[repositoryID]?.removeAll { $0.folderName == folderName }
        dirtyMetadata = true
        saveToDisk()
    }

    func updateLastActivity(folderName: String, repositoryID: UUID) {
        if let index = worktreeMetadata[repositoryID]?.firstIndex(where: { $0.folderName == folderName }) {
            worktreeMetadata[repositoryID]?[index].lastActivityAt = Date()
        } else {
            var existing = worktreeMetadata[repositoryID] ?? []
            existing.append(WorktreeMetadata(folderName: folderName, lastActivityAt: Date()))
            worktreeMetadata[repositoryID] = existing
        }
        dirtyMetadata = true
        saveToDisk()
    }

    func updateCustomName(folderName: String, customName: String?, repositoryID: UUID) {
        guard let index = worktreeMetadata[repositoryID]?.firstIndex(where: { $0.folderName == folderName }) else {
            return
        }
        let sanitized = customName.flatMap { name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        worktreeMetadata[repositoryID]?[index].customName = sanitized
        dirtyMetadata = true
        saveToDisk()
    }

    // MARK: - Env Copy Overrides

    func getEnvCopyOverride(for repositoryID: UUID) -> Bool? {
        return envCopyOverrides[repositoryID]
    }

    func setEnvCopyOverride(repositoryID: UUID, enabled: Bool) {
        envCopyOverrides[repositoryID] = enabled
        dirtyOverrides = true
        saveToDisk()
    }

    func removeEnvCopyOverride(repositoryID: UUID) {
        envCopyOverrides.removeValue(forKey: repositoryID)
        dirtyOverrides = true
        saveToDisk()
    }

    // MARK: - Persistence

    private func saveToDisk() {
        guard dirtyRepos || dirtyMetadata || dirtyOverrides else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        // Only encode and write data that was actually modified.
        // Clear dirty flag only on successful write so failures are retried.
        if dirtyRepos {
            if let data = try? encoder.encode(repositories) {
                if atomicWrite(data: data, to: repositoriesFileURL) {
                    dirtyRepos = false
                }
            }
        }
        if dirtyMetadata {
            let stringKeyed = Dictionary(
                uniqueKeysWithValues: worktreeMetadata.map { ($0.key.uuidString, $0.value) }
            )
            if let data = try? encoder.encode(stringKeyed) {
                if atomicWrite(data: data, to: metadataFileURL) {
                    dirtyMetadata = false
                }
            }
        }
        if dirtyOverrides {
            let stringKeyed = Dictionary(
                uniqueKeysWithValues: envCopyOverrides.map { ($0.key.uuidString, $0.value) }
            )
            if let data = try? encoder.encode(stringKeyed) {
                if atomicWrite(data: data, to: envCopyOverridesFileURL) {
                    dirtyOverrides = false
                }
            }
        }
    }

    @discardableResult
    private func atomicWrite(data: Data, to destinationURL: URL) -> Bool {
        let fm = FileManager.default
        let directory = destinationURL.deletingLastPathComponent()
        let tempURL = directory.appendingPathComponent(UUID().uuidString + ".tmp")

        do {
            try data.write(to: tempURL)

            if fm.fileExists(atPath: destinationURL.path) {
                // Replace existing file, keeping the old one as .backup
                _ = try fm.replaceItemAt(
                    destinationURL,
                    withItemAt: tempURL,
                    backupItemName: destinationURL.lastPathComponent + ".backup"
                )
            } else {
                // First write — just move the temp file into place
                try fm.moveItem(at: tempURL, to: destinationURL)
            }
            return true
        } catch {
            Self.logger.error("Failed to write \(destinationURL.lastPathComponent): \(error.localizedDescription)")
            try? fm.removeItem(at: tempURL)
            return false
        }
    }
}
