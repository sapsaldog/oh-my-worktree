import Foundation

/// Computes the menu bar status-item title from the user's "show worktree name"
/// preference and the current selection. Extracted as a pure function so the
/// logic is testable (the `AppDelegate` that calls it is coverage-excluded).
enum MenuBarTitle {

    /// `UserDefaults` / `@AppStorage` key backing the "Show worktree name in
    /// menu bar" toggle. Default is `false` (icon only).
    static let showWorktreeNameKey = "showWorktreeNameInMenuBar"

    /// Resolves the status-item title.
    ///
    /// - Parameters:
    ///   - showWorktreeName: the user's toggle. When `false`, returns `""` so the
    ///     status item shows only its icon.
    ///   - repoName: the selected repository name, or `nil`.
    ///   - worktreeName: the resolved worktree label, or `nil`.
    /// - Returns: the title string (with a leading space separating it from the
    ///   icon), or `""` when the toggle is off.
    static func text(showWorktreeName: Bool, repoName: String?, worktreeName: String?) -> String {
        guard showWorktreeName else { return "" }
        guard let repoName else { return " Oh My Worktree" }
        if let worktreeName { return " \(repoName)/\(worktreeName)" }
        return " \(repoName)"
    }
}
