import Testing

@testable import OhMyWorktree

@Suite
struct RandomNameGeneratorTests {

    // MARK: - uniqueName (pure, deterministic)

    @Test func uniqueName_noCollision_returnsBase() {
        let result = RandomNameGenerator.uniqueName(base: "tokyo-river", existing: [])
        #expect(result == "tokyo-river")
    }

    @Test func uniqueName_oneCollision_appendsV2() {
        let result = RandomNameGenerator.uniqueName(
            base: "tokyo-river",
            existing: ["tokyo-river"]
        )
        #expect(result == "tokyo-river-v2")
    }

    @Test func uniqueName_chainedCollision_appendsNextVersion() {
        let result = RandomNameGenerator.uniqueName(
            base: "tokyo-river",
            existing: ["tokyo-river", "tokyo-river-v2"]
        )
        #expect(result == "tokyo-river-v3")
    }

    // MARK: - generate (exercises random selection)

    @Test func generate_emptyExisting_producesHyphenatedName() {
        let name = RandomNameGenerator.generate(existingFolderNames: [])
        let parts = name.split(separator: "-")
        #expect(parts.count == 2)
        #expect(false == name.isEmpty)
    }
}
