import Foundation

final class ExternalToolLauncher {

    // MARK: - iTerm

    func openInITerm(path: String, mode: AppSettings.OpenMode = .newTab) async throws {
        guard isITermInstalled() else {
            throw OhMyWorktreeError.externalToolNotFound(tool: "iTerm")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [path, "-a", "iTerm"]
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - Ghostty

    func openInGhostty(path: String) async throws {
        guard isGhosttyInstalled() else {
            throw OhMyWorktreeError.externalToolNotFound(tool: "Ghostty")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Ghostty", path]
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - VSCode

    func openInVSCode(path: String, mode: AppSettings.OpenMode = .newWindow) async throws {
        let codePath = try findVSCodeCLI()

        var arguments: [String] = []
        switch mode {
        case .newWindow:
            arguments = ["-n", path]
        case .newTab, .currentWindow:
            arguments = ["-r", path]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codePath)
        process.arguments = arguments

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw OhMyWorktreeError.commandExecutionFailed(
                command: "code",
                stderr: "Failed to open VSCode"
            )
        }
    }

    // MARK: - Cursor

    func openInCursor(path: String) async throws {
        guard isCursorInstalled() else {
            throw OhMyWorktreeError.externalToolNotFound(tool: "Cursor")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [path, "-a", "Cursor"]
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - Tool Detection

    func isITermInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/iTerm.app")
    }

    func isGhosttyInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/Ghostty.app")
    }

    func isVSCodeInstalled() -> Bool {
        return (try? findVSCodeCLI()) != nil
    }

    func isCursorInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
    }

    // MARK: - Private Helpers

    private func findVSCodeCLI() throws -> String {
        let possiblePaths = [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        throw OhMyWorktreeError.externalToolNotFound(tool: "Visual Studio Code")
    }

}
