import Foundation

struct AppSettings: Codable {
    var menuBarEnabled: Bool = true
    var iTermOpenMode: OpenMode = .newTab
    var vscodeOpenMode: OpenMode = .newWindow
    var lastSelectedRepositoryID: UUID?

    enum OpenMode: String, Codable, CaseIterable {
        case newTab
        case newWindow
        case currentWindow
    }
}
