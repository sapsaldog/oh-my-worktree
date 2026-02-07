import Foundation

actor RepositoryStore {
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

        // Load repositories
        let repoURL = repositoriesFileURL
        if let data = try? Data(contentsOf: repoURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([Repository].self, from: data) {
                repositories = decoded
            }
        }

        // Load metadata
        let metaURL = metadataFileURL
        if let data = try? Data(contentsOf: metaURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([String: [WorktreeMetadata]].self, from: data) {
                var result: [UUID: [WorktreeMetadata]] = [:]
                for (key, value) in decoded {
                    if let uuid = UUID(uuidString: key) {
                        result[uuid] = value
                    }
                }
                worktreeMetadata = result
            }
        }

        // Load env copy overrides
        let overridesURL = envCopyOverridesFileURL
        if let data = try? Data(contentsOf: overridesURL) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([String: Bool].self, from: data) {
                for (key, value) in decoded {
                    if let uuid = UUID(uuidString: key) {
                        envCopyOverrides[uuid] = value
                    }
                }
            }
        }
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

        // Save repositories
        if let data = try? encoder.encode(repositories) {
            try? data.write(to: repositoriesFileURL)
        }

        // Save metadata - convert UUID keys to String keys for JSON
        let stringKeyedMetadata = Dictionary(
            uniqueKeysWithValues: worktreeMetadata.map { (key, value) in
                (key.uuidString, value)
            }
        )
        if let data = try? encoder.encode(stringKeyedMetadata) {
            try? data.write(to: metadataFileURL)
        }

        // Save env copy overrides
        let stringKeyedOverrides = Dictionary(
            uniqueKeysWithValues: envCopyOverrides.map { (key, value) in
                (key.uuidString, value)
            }
        )
        if let data = try? encoder.encode(stringKeyedOverrides) {
            try? data.write(to: envCopyOverridesFileURL)
        }
    }
}
