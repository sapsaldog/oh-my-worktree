import Foundation
import Testing

@testable import OhMyWorktree

struct ExternalToolLauncherTests {

    // MARK: - cmux Protocol

    private final class SendRecorder {
        var commands: [String] = []
        var workspaceID = "WS-1234"

        func send(_ cmd: String) throws -> String {
            commands.append(cmd)
            if cmd == "new_workspace" {
                return "OK \(workspaceID)"
            }
            return "OK"
        }
    }

    @Test func runCmuxOpenProtocol_emitsExpectedSequence() throws {
        let recorder = SendRecorder()
        try ExternalToolLauncher.runCmuxOpenProtocol(
            path: "/short/path",
            chunkSize: 40,
            send: recorder.send
        )

        #expect(recorder.commands == [
            "new_workspace",
            "select_workspace WS-1234",
            "send cd /short/path",
            "send_key enter"
        ])
    }

    @Test func runCmuxOpenProtocol_chunksLongPaths() throws {
        let recorder = SendRecorder()
        let path = "/Users/sapsaldog/oh-my-worktree/workspaces/translator-pro-752884/monaco-zenith"
        try ExternalToolLauncher.runCmuxOpenProtocol(
            path: path,
            chunkSize: 40,
            send: recorder.send
        )

        let sendCalls = recorder.commands.filter { $0.hasPrefix("send ") && !$0.hasPrefix("send_key") }
        #expect(sendCalls.count > 1, "Long path should split into multiple send calls")

        let typedText = sendCalls.map { String($0.dropFirst("send ".count)) }.joined()
        #expect(typedText == "cd \(path)")
    }

    @Test func runCmuxOpenProtocol_lastCommandIsEnter() throws {
        let recorder = SendRecorder()
        try ExternalToolLauncher.runCmuxOpenProtocol(
            path: "/any/path",
            chunkSize: 40,
            send: recorder.send
        )
        #expect(recorder.commands.last == "send_key enter")
    }

    @Test func runCmuxOpenProtocol_extractsWorkspaceID() throws {
        let recorder = SendRecorder()
        recorder.workspaceID = "ABCD-EFGH"
        try ExternalToolLauncher.runCmuxOpenProtocol(
            path: "/x",
            chunkSize: 40,
            send: recorder.send
        )
        #expect(recorder.commands.contains("select_workspace ABCD-EFGH"))
    }

    @Test(arguments: [10, 20, 40, 100])
    func runCmuxOpenProtocol_eachChunkRespectsChunkSize(chunkSize: Int) throws {
        let recorder = SendRecorder()
        let longPath = String(repeating: "a", count: 200)
        try ExternalToolLauncher.runCmuxOpenProtocol(
            path: longPath,
            chunkSize: chunkSize,
            send: recorder.send
        )

        let sendCalls = recorder.commands.filter { $0.hasPrefix("send ") && !$0.hasPrefix("send_key") }
        for call in sendCalls {
            let payload = String(call.dropFirst("send ".count))
            #expect(payload.count <= chunkSize, "Chunk '\(payload)' exceeds chunkSize \(chunkSize)")
        }
    }

    @Test func runCmuxOpenProtocol_pathWithExactlyChunkSizeIsSingleSend() throws {
        let recorder = SendRecorder()
        // cd + space + path = exactly 40 chars when path is 37 chars
        let path = String(repeating: "x", count: 37)
        try ExternalToolLauncher.runCmuxOpenProtocol(
            path: path,
            chunkSize: 40,
            send: recorder.send
        )
        let sendCalls = recorder.commands.filter { $0.hasPrefix("send ") && !$0.hasPrefix("send_key") }
        #expect(sendCalls == ["send cd \(path)"])
    }

    @Test func runCmuxOpenProtocol_propagatesSendErrors() {
        struct StubError: Error {}
        var callCount = 0
        let send: (String) throws -> String = { _ in
            callCount += 1
            if callCount == 2 { throw StubError() }
            return "OK WS"
        }

        #expect(throws: StubError.self) {
            try ExternalToolLauncher.runCmuxOpenProtocol(
                path: "/p",
                chunkSize: 40,
                send: send
            )
        }
        #expect(callCount == 2, "Should stop at the failing call")
    }

    // MARK: - cmux Socket Path Resolution

    @Test func resolveCmuxSocketPath_readsModernStatePointer() {
        let home = URL(fileURLWithPath: "/Users/test")
        let modernPointer = home.appendingPathComponent(".local/state/cmux/last-socket-path").path
        let resolved = ExternalToolLauncher.resolveCmuxSocketPath(
            home: home,
            readPointer: { $0.path == modernPointer ? "/custom/live/cmux.sock\n" : nil }
        )
        #expect(resolved == "/custom/live/cmux.sock")
    }

    @Test func resolveCmuxSocketPath_usesModernDefaultWhenNoPointer() {
        let home = URL(fileURLWithPath: "/Users/test")
        let resolved = ExternalToolLauncher.resolveCmuxSocketPath(
            home: home,
            readPointer: { _ in nil }
        )
        #expect(resolved == "/Users/test/.local/state/cmux/cmux.sock")
    }

    @Test func resolveCmuxSocketPath_usesModernDefaultWhenPointerBlank() {
        let home = URL(fileURLWithPath: "/Users/test")
        let resolved = ExternalToolLauncher.resolveCmuxSocketPath(
            home: home,
            readPointer: { _ in "   \n" }
        )
        #expect(resolved == "/Users/test/.local/state/cmux/cmux.sock")
    }

    @Test func resolveCmuxSocketPath_trimsSurroundingWhitespace() {
        let home = URL(fileURLWithPath: "/Users/test")
        let resolved = ExternalToolLauncher.resolveCmuxSocketPath(
            home: home,
            readPointer: { _ in "  /custom/live/cmux.sock  \n" }
        )
        #expect(resolved == "/custom/live/cmux.sock")
    }
}
