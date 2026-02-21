import Foundation

actor RepositoryStore {
    static let shared = RepositoryStore()

    private var repositories: [Repository] = []
    private var worktreeMetadata: [UUID: [WorktreeMetadata]] = [:] // keyed by repository ID
    private var envCopyOverrides: [UUID: Bool] = [:]

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

    init() {
        // Ensure storage directory exists before loading
        let storageDir = storageDirectory
        if !FileManager.default.fileExists(atPath: storageDir.path) {
            try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Load repositories (with backup fallback)
        repositories = Self.loadJSON(
            from: repositoriesFileURL,
            type: [Repository].self,
            decoder: decoder
        ) ?? []

        // Load metadata (with backup fallback)
        if let decoded: [String: [WorktreeMetadata]] = Self.loadJSON(
            from: metadataFileURL,
            type: [String: [WorktreeMetadata]].self,
            decoder: decoder
        ) {
            var result: [UUID: [WorktreeMetadata]] = [:]
            for (key, value) in decoded {
                if let uuid = UUID(uuidString: key) {
                    result[uuid] = value
                }
            }
            worktreeMetadata = result
        }

        // Load env copy overrides (with backup fallback)
        if let decoded: [String: Bool] = Self.loadJSON(
            from: envCopyOverridesFileURL,
            type: [String: Bool].self,
            decoder: decoder
        ) {
            for (key, value) in decoded {
                if let uuid = UUID(uuidString: key) {
                    envCopyOverrides[uuid] = value
                }
            }
        }
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
        saveToDisk()
    }

    func removeRepository(id: UUID) {
        repositories.removeAll { $0.id == id }
        worktreeMetadata.removeValue(forKey: id)
        envCopyOverrides.removeValue(forKey: id)
        saveToDisk()
    }

    func updateRepository(_ repository: Repository) {
        guard let index = repositories.firstIndex(where: { $0.id == repository.id }) else { return }
        repositories[index] = repository
        saveToDisk()
    }

    func getRepository(id: UUID) -> Repository? {
        return repositories.first { $0.id == id }
    }

    func updateLastAccessed(id: UUID) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        repositories[index].lastAccessedAt = Date()
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
        saveToDisk()
    }

    func removeWorktreeMetadata(folderName: String, repositoryID: UUID) {
        worktreeMetadata[repositoryID]?.removeAll { $0.folderName == folderName }
        saveToDisk()
    }

    func updateLastActivity(folderName: String, repositoryID: UUID) {
        if let index = worktreeMetadata[repositoryID]?.firstIndex(where: { $0.folderName == folderName }) {
            worktreeMetadata[repositoryID]?[index].lastActivityAt = Date()
        } else {
            // Create metadata entry if it doesn't exist yet
            var existing = worktreeMetadata[repositoryID] ?? []
            existing.append(WorktreeMetadata(folderName: folderName, lastActivityAt: Date()))
            worktreeMetadata[repositoryID] = existing
        }
        saveToDisk()
    }

    // MARK: - Env Copy Overrides

    func getEnvCopyOverride(for repositoryID: UUID) -> Bool? {
        return envCopyOverrides[repositoryID]
    }

    func setEnvCopyOverride(repositoryID: UUID, enabled: Bool) {
        envCopyOverrides[repositoryID] = enabled
        saveToDisk()
    }

    func removeEnvCopyOverride(repositoryID: UUID) {
        envCopyOverrides.removeValue(forKey: repositoryID)
        saveToDisk()
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        // Encode ALL data first — if any encoding fails, write nothing
        let stringKeyedMetadata = Dictionary(
            uniqueKeysWithValues: worktreeMetadata.map { (key, value) in
                (key.uuidString, value)
            }
        )
        let stringKeyedOverrides = Dictionary(
            uniqueKeysWithValues: envCopyOverrides.map { (key, value) in
                (key.uuidString, value)
            }
        )

        guard let repoData = try? encoder.encode(repositories),
              let metaData = try? encoder.encode(stringKeyedMetadata),
              let overridesData = try? encoder.encode(stringKeyedOverrides) else {
            return
        }

        // All encoding succeeded — write each file atomically
        atomicWrite(data: repoData, to: repositoriesFileURL)
        atomicWrite(data: metaData, to: metadataFileURL)
        atomicWrite(data: overridesData, to: envCopyOverridesFileURL)
    }

    private func atomicWrite(data: Data, to destinationURL: URL) {
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
        } catch {
            // Clean up temp file on failure
            try? fm.removeItem(at: tempURL)
        }
    }
}
