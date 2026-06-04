import Foundation
import KeyboardShortcuts

/// Identifies each configurable keyboard shortcut in the app.
enum ShortcutAction: String, CaseIterable {
    case globalHotkey
    case openSettings
    case addRepository
    case addWorktree
    case removeWorktree
    case forceRemoveWorktree
    case quickRemoveWorktree
    case openITerm
    case openGhostty
    case openVSCode
    case openCursor
    case openCmux
    case refreshWorktrees
    case gitPull
    case showInFinder
    case copyPath

    /// The default key combo string for this action.
    var defaultCombo: String {
        switch self {
        case .globalHotkey: "⌥⇧W"
        case .openSettings: "⌘,"
        case .addRepository: "⌘⇧N"
        case .addWorktree: "⌘N"
        case .removeWorktree: "⌫"
        case .forceRemoveWorktree: "⌘⌫"
        case .quickRemoveWorktree: "⇧⌘⌫"
        case .openITerm: "⌘⇧I"
        case .openGhostty: "⌘⇧G"
        case .openVSCode: "⌘⇧V"
        case .openCursor: "⌘⇧C"
        case .openCmux: "⌘⇧M"
        case .refreshWorktrees: "⌘R"
        case .gitPull: "⌘P"
        case .showInFinder: "⌘O"
        case .copyPath: "⌘C"
        }
    }

    /// The UserDefaults key used to persist custom combos.
    var userDefaultsKey: String {
        "shortcut.\(rawValue)"
    }

    /// Human-readable label for the Settings UI.
    var displayName: String {
        switch self {
        case .globalHotkey: "Toggle Menu Bar Popup"
        case .openSettings: "Open Settings"
        case .addRepository: "Add Repository"
        case .addWorktree: "New Worktree"
        case .removeWorktree: "Remove Worktree"
        case .forceRemoveWorktree: "Force Remove Worktree"
        case .quickRemoveWorktree: "Quick Remove Worktree"
        case .openITerm: "Open in iTerm"
        case .openGhostty: "Open in Ghostty"
        case .openVSCode: "Open in VSCode"
        case .openCursor: "Open in Cursor"
        case .openCmux: "Open in cmux"
        case .refreshWorktrees: "Refresh Worktrees"
        case .gitPull: "Git Pull"
        case .showInFinder: "Show in Finder"
        case .copyPath: "Copy Path"
        }
    }

    /// Whether this shortcut is a system-wide global hotkey (vs. in-app only).
    var isGlobal: Bool {
        self == .globalHotkey
    }

    /// The default shortcut for this action (KeyboardShortcuts representation).
    var defaultShortcut: KeyboardShortcuts.Shortcut {
        switch self {
        case .globalHotkey: .init(.w, modifiers: [.option, .shift])
        case .openSettings: .init(.comma, modifiers: [.command])
        case .addRepository: .init(.n, modifiers: [.command, .shift])
        case .addWorktree: .init(.n, modifiers: [.command])
        case .removeWorktree: .init(.delete, modifiers: [])
        case .forceRemoveWorktree: .init(.delete, modifiers: [.command])
        case .quickRemoveWorktree: .init(.delete, modifiers: [.command, .shift])
        case .openITerm: .init(.i, modifiers: [.command, .shift])
        case .openGhostty: .init(.g, modifiers: [.command, .shift])
        case .openVSCode: .init(.v, modifiers: [.command, .shift])
        case .openCursor: .init(.c, modifiers: [.command, .shift])
        case .openCmux: .init(.m, modifiers: [.command, .shift])
        case .refreshWorktrees: .init(.r, modifiers: [.command])
        case .gitPull: .init(.p, modifiers: [.command])
        case .showInFinder: .init(.o, modifiers: [.command])
        case .copyPath: .init(.c, modifiers: [.command])
        }
    }
}
