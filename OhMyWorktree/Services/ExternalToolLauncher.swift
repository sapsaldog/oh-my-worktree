import Foundation
import os

final class ExternalToolLauncher: Sendable {

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

    // MARK: - cmux

    private static let cmuxAccessDeniedMessage =
        "cmux socket access denied. Open cmux Settings → Automation → Socket Control Mode → " +
        "set to \"Full open access\", then restart cmux."

    func openInCmux(path: String) async throws {
        guard isCmuxInstalled() else {
            throw OhMyWorktreeError.externalToolNotFound(tool: "cmux")
        }

        let socketPath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("cmux/cmux.sock")
            .path

        // If cmux is not running, launch it and wait for the socket
        if !FileManager.default.fileExists(atPath: socketPath) {
            let launchProcess = Process()
            launchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            launchProcess.arguments = ["-a", "cmux"]
            try launchProcess.run()
            launchProcess.waitUntilExit()

            try await waitForFile(atPath: socketPath, timeout: 5)
            guard FileManager.default.fileExists(atPath: socketPath) else {
                throw OhMyWorktreeError.commandExecutionFailed(
                    command: "cmux",
                    stderr: "cmux did not start within 5 seconds"
                )
            }
        }

        try cmuxSocketCommand(socketPath: socketPath) { send in
            let result = try send("new_workspace")
            let workspaceID = result.replacingOccurrences(of: "OK ", with: "")
            _ = try send("select_workspace \(workspaceID)")
            _ = try send("send cd \(path)")
            _ = try send("send_key enter")
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

    func isCursorInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
    }

    func isCmuxInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/cmux.app")
    }

    // MARK: - Private Helpers

    private func findVSCodeCLI() throws -> String {
        let possiblePaths = [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        ]

        for path in possiblePaths where FileManager.default.fileExists(atPath: path) {
            return path
        }

        throw OhMyWorktreeError.externalToolNotFound(tool: "Visual Studio Code")
    }

    private func cmuxSocketCommand(socketPath: String, commands: (_ send: (String) throws -> String) throws -> Void) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw OhMyWorktreeError.commandExecutionFailed(command: "cmux", stderr: "Failed to create socket")
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path) - 1  // -1 for null terminator
        guard socketPath.utf8.count <= maxPathLength else {
            throw OhMyWorktreeError.commandExecutionFailed(
                command: "cmux",
                stderr: "Socket path too long: \(socketPath)"
            )
        }
        socketPath.withCString { src in
            withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
                let dest = rawBuf.baseAddress!.assumingMemoryBound(to: CChar.self)
                strlcpy(dest, src, rawBuf.count)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw OhMyWorktreeError.commandExecutionFailed(command: "cmux", stderr: "Failed to connect to cmux socket")
        }

        let sendCommand: (String) throws -> String = { command in
            let message = command + "\n"
            _ = message.withCString { ptr in
                Darwin.send(fd, ptr, strlen(ptr), 0)
            }

            usleep(100_000)
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = recv(fd, &buffer, buffer.count, 0)
            guard bytesRead > 0 else {
                throw OhMyWorktreeError.commandExecutionFailed(command: "cmux \(command)", stderr: "No response")
            }
            let rawResponse = String(bytes: buffer[..<bytesRead], encoding: .utf8)
            let response = rawResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !response.hasPrefix("ERROR") else {
                if response.contains("Access denied") {
                    throw OhMyWorktreeError.commandExecutionFailed(
                        command: "cmux",
                        stderr: Self.cmuxAccessDeniedMessage
                    )
                }
                throw OhMyWorktreeError.commandExecutionFailed(command: "cmux \(command)", stderr: response)
            }
            return response
        }

        try commands(sendCommand)
    }

    // MARK: - File Monitoring

    /// Waits for a file to appear using DispatchSource file system monitoring.
    /// No polling or arbitrary delays — reacts to actual file system events.
    private func waitForFile(atPath path: String, timeout: TimeInterval) async throws {
        if FileManager.default.fileExists(atPath: path) { return }

        let directory = (path as NSString).deletingLastPathComponent
        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let resumed = OSAllocatedUnfairLock(initialState: false)
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fd, eventMask: .write, queue: .global()
                )
                await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        source.setEventHandler {
                            if FileManager.default.fileExists(atPath: path) {
                                source.cancel()
                                if resumed.withLock({ let old = $0; $0 = true; return !old }) {
                                    continuation.resume()
                                }
                            }
                        }
                        source.setCancelHandler {
                            close(fd)
                            if resumed.withLock({ let old = $0; $0 = true; return !old }) {
                                continuation.resume()
                            }
                        }
                        source.resume()

                        if FileManager.default.fileExists(atPath: path) {
                            source.cancel()
                            if resumed.withLock({ let old = $0; $0 = true; return !old }) {
                                continuation.resume()
                            }
                        }
                    }
                } onCancel: {
                    source.cancel()
                }
            }
            group.addTask {
                // swiftlint:disable:next no_arbitrary_delay
                try await Task.sleep(for: .seconds(timeout))
                throw OhMyWorktreeError.commandExecutionFailed(
                    command: "waitForFile",
                    stderr: "File did not appear within \(Int(timeout)) seconds: \(path)"
                )
            }
            do {
                _ = try await group.next()
                group.cancelAll()
                while !group.isEmpty { _ = try? await group.next() }
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}
