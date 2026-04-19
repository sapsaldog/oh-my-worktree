import Foundation

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
}
