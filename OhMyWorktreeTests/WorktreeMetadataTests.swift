import Foundation
import Testing

@testable import OhMyWorktree

@Suite struct WorktreeMetadataTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - customName encode/decode

    @Test func encodeDecode_withCustomName() throws {
        let metadata = WorktreeMetadata(folderName: "bright-ocean", customName: "My Feature")

        let data = try encoder.encode(metadata)
        let decoded = try decoder.decode(WorktreeMetadata.self, from: data)

        #expect(decoded.folderName == "bright-ocean")
        #expect(decoded.customName == "My Feature")
    }

    @Test func encodeDecode_withNilCustomName() throws {
        let metadata = WorktreeMetadata(folderName: "bright-ocean")

        let data = try encoder.encode(metadata)
        let decoded = try decoder.decode(WorktreeMetadata.self, from: data)

        #expect(decoded.folderName == "bright-ocean")
        #expect(decoded.customName == nil)
    }

    @Test func decode_backwardCompatibility_withoutCustomNameField() throws {
        let json = """
        {
            "folderName": "bright-ocean",
            "createdAt": "2026-02-27T00:00:00Z",
            "lastActivityAt": "2026-02-27T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try decoder.decode(WorktreeMetadata.self, from: data)

        #expect(decoded.folderName == "bright-ocean")
        #expect(decoded.customName == nil)
    }
}
