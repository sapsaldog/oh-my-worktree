import Foundation

struct WorktreeMetadata: Codable, Hashable {
    let folderName: String
    let createdAt: Date
    var lastActivityAt: Date
    var customName: String?

    init(folderName: String, createdAt: Date = Date(), lastActivityAt: Date? = nil, customName: String? = nil) {
        self.folderName = folderName
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt ?? createdAt
        self.customName = customName
    }
}
