import Foundation
import AppKit

final class ExternalToolLauncher {

    // MARK: - iTerm

    func openInITerm(path: String, mode: AppSettings.OpenMode = .newTab) async throws {
        guard isITermInstalled() else {
            throw OhMyWorktreeError.externalToolNotFound(tool: "iTerm")
        }

        let script: String
        switch mode {
        case .newTab:
            script = """
            tell application "iTerm"
                activate
                tell current window
                    create tab with default profile
                    tell current session
                        write text "cd \\"\(path)\\""
                    end tell
                end tell
            end tell
            """
        case .newWindow:
            script = """
            tell application "iTerm"
                activate
                create window with default profile
                tell current session of current window
                    write text "cd \\"\(path)\\""
                end tell
            end tell
            """
        case .currentWindow:
            script = """
            tell application "iTerm"
                activate
                tell current session of current window
                    write text "cd \\"\(path)\\""
                end tell
            end tell
            """
        }

        try await runAppleScript(script)
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

    private func runAppleScript(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                script?.executeAndReturnError(&error)

                if let error = error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: OhMyWorktreeError.commandExecutionFailed(
                        command: "AppleScript",
                        stderr: message
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
