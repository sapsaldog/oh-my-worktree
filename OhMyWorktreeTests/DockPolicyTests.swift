import AppKit
import Testing

@testable import OhMyWorktree

@Suite
struct DockPolicyTests {

    @Test func defaultsKeyIsStable() {
        #expect(DockPolicy.defaultsKey == "showInDock")
    }

    @Test func accessoryWhenIdleAndNotPinned() {
        #expect(DockPolicy.activationPolicy(
            showInDock: false, hasAppWindows: false, updaterSessionActive: false
        ) == .accessory)
    }

    @Test func regularWhenPinnedEvenWithoutWindows() {
        #expect(DockPolicy.activationPolicy(
            showInDock: true, hasAppWindows: false, updaterSessionActive: false
        ) == .regular)
    }

    @Test func regularWhenWindowOpenEvenIfNotPinned() {
        #expect(DockPolicy.activationPolicy(
            showInDock: false, hasAppWindows: true, updaterSessionActive: false
        ) == .regular)
    }

    @Test func regularWhenPinnedAndWindowOpen() {
        #expect(DockPolicy.activationPolicy(
            showInDock: true, hasAppWindows: true, updaterSessionActive: false
        ) == .regular)
    }

    // MARK: - Updater session

    /// A user-initiated update check must keep the app `.regular` even with no
    /// windows open: Sparkle's "up to date" / error alerts otherwise end up
    /// behind other apps when the policy reverts to `.accessory` mid-session.
    @Test func regularDuringUpdaterSessionEvenWithoutWindows() {
        #expect(DockPolicy.activationPolicy(
            showInDock: false, hasAppWindows: false, updaterSessionActive: true
        ) == .regular)
    }

    @Test func regularDuringUpdaterSessionWithWindowOpen() {
        #expect(DockPolicy.activationPolicy(
            showInDock: false, hasAppWindows: true, updaterSessionActive: true
        ) == .regular)
    }

    @Test func accessoryAgainAfterUpdaterSessionEnds() {
        #expect(DockPolicy.activationPolicy(
            showInDock: false, hasAppWindows: false, updaterSessionActive: false
        ) == .accessory)
    }

    // MARK: - Session-state notification payload

    @Test func updaterSessionActiveKeyIsStable() {
        #expect(DockPolicy.updaterSessionActiveKey == "updaterSessionActive")
    }

    @Test func updaterSessionActiveParsesTrue() {
        let userInfo: [AnyHashable: Any] = [DockPolicy.updaterSessionActiveKey: true]
        #expect(DockPolicy.updaterSessionActive(from: userInfo) == true)
    }

    @Test func updaterSessionActiveParsesFalse() {
        let userInfo: [AnyHashable: Any] = [DockPolicy.updaterSessionActiveKey: false]
        #expect(DockPolicy.updaterSessionActive(from: userInfo) == false)
    }

    @Test func updaterSessionActiveDefaultsToFalseWhenKeyMissing() {
        #expect(DockPolicy.updaterSessionActive(from: [:]) == false)
    }

    @Test func updaterSessionActiveDefaultsToFalseWhenUserInfoNil() {
        #expect(DockPolicy.updaterSessionActive(from: nil) == false)
    }

    @Test func updaterSessionActiveDefaultsToFalseWhenValueNotBool() {
        let userInfo: [AnyHashable: Any] = [DockPolicy.updaterSessionActiveKey: "yes"]
        #expect(DockPolicy.updaterSessionActive(from: userInfo) == false)
    }
}
