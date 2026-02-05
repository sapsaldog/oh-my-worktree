import Foundation

struct WorktreeMetadata: Codable, Hashable {
    let folderName: String
    let createdAt: Date
    var lastActivityAt: Date

    init(folderName: String, createdAt: Date = Date(), lastActivityAt: Date? = nil) {
        self.folderName = folderName
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt ?? createdAt
    }
}
