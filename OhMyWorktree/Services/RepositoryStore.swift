import Foundation
import os

actor RepositoryStore {
    static let shared = RepositoryStore()

    /// Crash reporter for capturing errors that would otherwise be silently swallowed.
    /// Defaults to the app-wide reporter; tests can inject a no-op or mock.
    nonisolated let crashReporter: CrashReporter

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

    private init(crashReporter: CrashReporter? = nil) {
        self.crashReporter = crashReporter ?? CrashReporterProvider.shared
        // Compute URLs locally — nonisolated computed properties reference `self`,
        // which cannot be used before all stored properties are initialized.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storageDir = appSupport.appendingPathComponent("OhMyWorktree", isDirectory: true)

        if !FileManager.default.fileExists(atPath: storageDir.path) {
            do {
                try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
            } catch {
                Self.logger.error("Failed to create storage directory: \(error.localizedDescription)")
                self.crashReporter.capture(error: error, context: [
                    "operation": "createStorageDirectory",
                    "path": storageDir.path
                ])
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Load into locals first, then assign to self in three definite-initialization
        // writes at the end. Swift 6 permits `self.x = value` in a nonisolated actor
        // init only when it is the *first* (definite) assignment to that property.
        let reporter = self.crashReporter
        reporter.addBreadcrumb(message: "Loading persisted data from disk", category: "persistence")

        let loadedRepos: [Repository] = Self.loadJSON(
            from: storageDir.appendingPathComponent("repositories.json"),
            type: [Repository].self,
            decoder: decoder,
            crashReporter: reporter
        ) ?? []

        var loadedMetadata: [UUID: [WorktreeMetadata]] = [:]
        if let decoded: [String: [WorktreeMetadata]] = Self.loadJSON(
            from: storageDir.appendingPathComponent("worktree_metadata.json"),
            type: [String: [WorktreeMetadata]].self,
            decoder: decoder,
            crashReporter: reporter
        ) {
            for (key, value) in decoded {
                if let uuid = UUID(uuidString: key) { loadedMetadata[uuid] = value }
            }
        }

        var loadedOverrides: [UUID: Bool] = [:]
        if let decoded: [String: Bool] = Self.loadJSON(
            from: storageDir.appendingPathComponent("env_copy_overrides.json"),
            type: [String: Bool].self,
            decoder: decoder,
            crashReporter: reporter
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
        decoder: JSONDecoder,
        crashReporter: CrashReporter
    ) -> T? {
        // 1st: try the primary file
        var primaryError: Error?
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            primaryError = error
        }

        // 2nd: try the .backup file
        let backupURL = url.appendingPathExtension("backup")
        do {
            let data = try Data(contentsOf: backupURL)
            return try decoder.decode(T.self, from: data)
        } catch {
            // Both failed — report if the primary file existed (not a first-launch scenario)
            let fileExists = FileManager.default.fileExists(atPath: url.path)
                || FileManager.default.fileExists(atPath: backupURL.path)
            if fileExists {
                logger.error("Failed to load \(url.lastPathComponent) from primary and backup")
                crashReporter.capture(error: error, context: [
                    "operation": "loadJSON",
                    "file": url.lastPathComponent,
                    "primaryError": primaryError?.localizedDescription ?? "unknown",
                    "backupError": error.localizedDescription
                ])
            }
        }

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

        crashReporter.addBreadcrumb(
            message: "Saving to disk (repos=\(dirtyRepos), meta=\(dirtyMetadata), overrides=\(dirtyOverrides))",
            category: "persistence"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        // Only encode and write data that was actually modified.
        // Clear dirty flag only on successful write so failures are retried.
        if dirtyRepos {
            do {
                let data = try encoder.encode(repositories)
                if atomicWrite(data: data, to: repositoriesFileURL) {
                    dirtyRepos = false
                }
            } catch {
                Self.logger.error("Failed to encode repositories: \(error.localizedDescription)")
                crashReporter.capture(error: error, context: [
                    "operation": "encodeRepositories",
                    "count": repositories.count
                ])
            }
        }
        if dirtyMetadata {
            let stringKeyed = Dictionary(
                uniqueKeysWithValues: worktreeMetadata.map { ($0.key.uuidString, $0.value) }
            )
            do {
                let data = try encoder.encode(stringKeyed)
                if atomicWrite(data: data, to: metadataFileURL) {
                    dirtyMetadata = false
                }
            } catch {
                Self.logger.error("Failed to encode metadata: \(error.localizedDescription)")
                crashReporter.capture(error: error, context: [
                    "operation": "encodeMetadata",
                    "count": worktreeMetadata.count
                ])
            }
        }
        if dirtyOverrides {
            let stringKeyed = Dictionary(
                uniqueKeysWithValues: envCopyOverrides.map { ($0.key.uuidString, $0.value) }
            )
            do {
                let data = try encoder.encode(stringKeyed)
                if atomicWrite(data: data, to: envCopyOverridesFileURL) {
                    dirtyOverrides = false
                }
            } catch {
                Self.logger.error("Failed to encode overrides: \(error.localizedDescription)")
                crashReporter.capture(error: error, context: [
                    "operation": "encodeOverrides",
                    "count": envCopyOverrides.count
                ])
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
            crashReporter.capture(error: error, context: [
                "operation": "atomicWrite",
                "file": destinationURL.lastPathComponent
            ])
            try? fm.removeItem(at: tempURL)
            return false
        }
    }
}
