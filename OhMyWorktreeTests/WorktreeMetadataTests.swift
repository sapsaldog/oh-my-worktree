import XCTest

@testable import OhMyWorktree

final class WorktreeMetadataTests: XCTestCase {

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

    func testEncodeDecode_withCustomName() throws {
        let metadata = WorktreeMetadata(folderName: "bright-ocean", customName: "My Feature")

        let data = try encoder.encode(metadata)
        let decoded = try decoder.decode(WorktreeMetadata.self, from: data)

        XCTAssertEqual(decoded.folderName, "bright-ocean")
        XCTAssertEqual(decoded.customName, "My Feature")
    }

    func testEncodeDecode_withNilCustomName() throws {
        let metadata = WorktreeMetadata(folderName: "bright-ocean")

        let data = try encoder.encode(metadata)
        let decoded = try decoder.decode(WorktreeMetadata.self, from: data)

        XCTAssertEqual(decoded.folderName, "bright-ocean")
        XCTAssertNil(decoded.customName)
    }

    func testDecode_backwardCompatibility_withoutCustomNameField() throws {
        // Simulate JSON from older version that doesn't have customName field
        let json = """
        {
            "folderName": "bright-ocean",
            "createdAt": "2026-02-27T00:00:00Z",
            "lastActivityAt": "2026-02-27T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try decoder.decode(WorktreeMetadata.self, from: data)

        XCTAssertEqual(decoded.folderName, "bright-ocean")
        XCTAssertNil(decoded.customName)
    }
}
