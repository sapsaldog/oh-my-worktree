import Foundation

struct AppSettings: Codable {
    var menuBarEnabled: Bool = true
    var iTermOpenMode: OpenMode = .newTab
    var vscodeOpenMode: OpenMode = .newWindow
    var lastSelectedRepositoryID: UUID?
    var globalHotkeyEnabled: Bool = true
    var globalHotkeyKeyCombo: String = "⌥⇧W"

    enum OpenMode: String, Codable, CaseIterable {
        case newTab
        case newWindow
        case currentWindow
    }
}
