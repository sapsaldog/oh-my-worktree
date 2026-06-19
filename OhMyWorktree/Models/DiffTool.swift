import Foundation

/// A pure, table-driven catalog of external diff/merge tools the app can hand a
/// copied file off to. Holds display metadata, the CLI invocation, and the
/// candidate command paths used for detection. All logic here is side-effect free
/// so it is fully unit-tested; the actual detection + `Process` launch live in the
/// coverage-excluded `DiffToolLauncher`.
struct DiffTool: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// SF Symbol used in the picker.
    let sfSymbol: String
    /// Flags inserted before the two file paths (e.g. VS Code's `--diff`).
    let extraArguments: [String]
    /// Absolute command paths tried in order; the first that exists wins.
    let commandCandidates: [String]

    /// Full argument vector for diffing `mainPath` (left) against `worktreePath` (right).
    func launchArguments(mainPath: String, worktreePath: String) -> [String] {
        extraArguments + [mainPath, worktreePath]
    }

    /// The five tools from the design, in display order.
    static let all: [DiffTool] = [
        DiffTool(
            id: "araxis", name: "Araxis Merge", sfSymbol: "rectangle.split.2x1",
            extraArguments: [],
            // Bundle path first: ImageMagick also installs a `compare` on PATH.
            commandCandidates: [
                "/Applications/Araxis Merge.app/Contents/Utilities/compare",
                "/usr/local/bin/compare"
            ]
        ),
        DiffTool(
            id: "kaleidoscope", name: "Kaleidoscope", sfSymbol: "circle.lefthalf.filled",
            extraArguments: [],
            commandCandidates: [
                "/usr/local/bin/ksdiff",
                "/opt/homebrew/bin/ksdiff",
                "/Applications/Kaleidoscope.app/Contents/Resources/bin/ksdiff"
            ]
        ),
        DiffTool(
            id: "bcompare", name: "Beyond Compare", sfSymbol: "arrow.left.arrow.right",
            extraArguments: [],
            commandCandidates: [
                "/usr/local/bin/bcomp",
                "/Applications/Beyond Compare.app/Contents/MacOS/bcomp"
            ]
        ),
        DiffTool(
            id: "vscode", name: "VS Code", sfSymbol: "chevron.left.forwardslash.chevron.right",
            extraArguments: ["--diff"],
            commandCandidates: [
                "/usr/local/bin/code",
                "/opt/homebrew/bin/code",
                "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
            ]
        ),
        DiffTool(
            id: "filemerge", name: "FileMerge", sfSymbol: "doc.on.doc",
            extraArguments: [],
            commandCandidates: ["/usr/bin/opendiff"]
        )
    ]

    static func find(id: String) -> DiffTool? {
        all.first { $0.id == id }
    }

    /// The subset of `all` for which `probe` returns true (probe = "is installed?").
    static func installed(probe: (DiffTool) -> Bool) -> [DiffTool] {
        all.filter(probe)
    }

    /// The tool that should actually be used: the stored choice if it is installed,
    /// otherwise the first installed tool, otherwise nil (nothing installed).
    static func effective(storedID: String?, installed: [DiffTool]) -> DiffTool? {
        installed.first { $0.id == storedID } ?? installed.first
    }
}
