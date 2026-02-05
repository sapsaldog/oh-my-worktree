import Foundation

struct Repository: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let path: String
    let createdAt: Date
    var lastAccessedAt: Date

    var isValid: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    init(id: UUID = UUID(), name: String, path: String, createdAt: Date = Date(), lastAccessedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }
}
