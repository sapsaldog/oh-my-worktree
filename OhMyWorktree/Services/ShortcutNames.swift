import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// System-wide hotkey that toggles the menu bar popup window.
    static let toggleMenuBarPopup = Self(
        "toggleMenuBarPopup",
        default: .init(.w, modifiers: [.option, .shift])
    )
}
