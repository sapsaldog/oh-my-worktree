import Foundation

struct RandomNameGenerator {
    private static let prefixes: [String] = [
        // Cities
        "tokyo", "paris", "seoul", "london", "berlin", "oslo", "rome", "miami",
        "cairo", "dubai", "lima", "kyoto", "porto", "zurich", "prague",
        "vienna", "lisbon", "nairobi", "havana", "dublin", "bali", "fiji",
        "malta", "monaco", "york", "osaka", "stockholm", "athens",
        // Adjectives
        "bright", "swift", "cosmic", "gentle", "bold", "quiet", "vivid",
        "golden", "silver", "amber", "coral", "azure", "jade", "ruby",
        "crisp", "warm", "cool", "rapid", "calm", "keen", "noble",
        "brave", "lucid", "witty", "agile", "polar", "stellar"
    ]

    private static let suffixes: [String] = [
        "ocean", "river", "mountain", "forest", "sky", "lunch", "pizza",
        "sunset", "meadow", "garden", "breeze", "storm", "flame", "frost",
        "bloom", "creek", "ridge", "grove", "delta", "coral", "prism",
        "spark", "drift", "quest", "pulse", "orbit", "nexus", "crest",
        "harbor", "summit", "canyon", "rapids", "beacon", "aurora", "zenith",
        "vertex", "bridge", "tower", "atlas", "comet", "eagle", "falcon",
        "panda", "lotus", "cedar", "maple", "tiger", "wolf", "hawk",
        "dawn", "dusk"
    ]

    static func generate(existingFolderNames: Set<String>) -> String {
        let prefix = prefixes.randomElement()!
        let suffix = suffixes.randomElement()!
        let base = "\(prefix)-\(suffix)"
        return uniqueName(base: base, existing: existingFolderNames)
    }

    /// Resolves a unique folder name from `base`, appending `-v<N>` on collision.
    static func uniqueName(base: String, existing: Set<String>) -> String {
        if !existing.contains(base) {
            return base
        }

        var version = 2
        while existing.contains("\(base)-v\(version)") {
            version += 1
        }
        return "\(base)-v\(version)"
    }
}
