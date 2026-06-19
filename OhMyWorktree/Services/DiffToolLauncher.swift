import Foundation

/// Detects installed external diff tools and launches one on a file pair.
/// The impure half of the diff-tool feature (filesystem probing + `Process`);
/// the testable catalog/arg logic lives in `DiffTool`. Coverage-excluded.
final class DiffToolLauncher: Sendable {

    private let fileExists: @Sendable (String) -> Bool

    init(fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.fileExists = fileExists
    }

    /// First existing command path for `tool`, or nil if none is present.
    func resolvedCommand(for tool: DiffTool) -> String? {
        tool.commandCandidates.first(where: fileExists)
    }

    func isInstalled(_ tool: DiffTool) -> Bool {
        resolvedCommand(for: tool) != nil
    }

    /// The installed subset of `DiffTool.all`, in catalog order.
    func installedTools() -> [DiffTool] {
        DiffTool.installed { isInstalled($0) }
    }

    /// Launches `tool` to diff `mainPath` (left) against `worktreePath` (right).
    /// Fire-and-forget: diff tools are long-lived GUI apps, so we do not wait.
    func launch(_ tool: DiffTool, mainPath: String, worktreePath: String) throws {
        guard let command = resolvedCommand(for: tool) else {
            throw OhMyWorktreeError.externalToolNotFound(tool: tool.name)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = tool.launchArguments(mainPath: mainPath, worktreePath: worktreePath)
        try process.run()
    }
}
