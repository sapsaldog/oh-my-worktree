import Foundation

struct WorktreeMetadata: Codable, Hashable {
    let folderName: String
    let createdAt: Date

    init(folderName: String, createdAt: Date = Date()) {
        self.folderName = folderName
        self.createdAt = createdAt
    }
}
