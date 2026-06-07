import AppKit
import Testing

@testable import OhMyWorktree

@Suite
struct DockPolicyTests {

    @Test func defaultsKeyIsStable() {
        #expect(DockPolicy.defaultsKey == "showInDock")
    }

    @Test func accessoryWhenIdleAndNotPinned() {
        #expect(DockPolicy.activationPolicy(showInDock: false, hasAppWindows: false) == .accessory)
    }

    @Test func regularWhenPinnedEvenWithoutWindows() {
        #expect(DockPolicy.activationPolicy(showInDock: true, hasAppWindows: false) == .regular)
    }

    @Test func regularWhenWindowOpenEvenIfNotPinned() {
        #expect(DockPolicy.activationPolicy(showInDock: false, hasAppWindows: true) == .regular)
    }

    @Test func regularWhenPinnedAndWindowOpen() {
        #expect(DockPolicy.activationPolicy(showInDock: true, hasAppWindows: true) == .regular)
    }
}
