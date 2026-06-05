import Foundation
import Testing

@testable import OhMyWorktree

@Suite
struct AppSettingsTests {

    @Test func defaultValues() {
        let settings = AppSettings()

        #expect(settings.menuBarEnabled == true)
        #expect(settings.iTermOpenMode == .newTab)
        #expect(settings.vscodeOpenMode == .newWindow)
        #expect(settings.lastSelectedRepositoryID == nil)
    }

    @Test func codableRoundTrip() throws {
        let original = AppSettings(
            menuBarEnabled: false,
            iTermOpenMode: .currentWindow,
            vscodeOpenMode: .newTab,
            lastSelectedRepositoryID: UUID()
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.menuBarEnabled == original.menuBarEnabled)
        #expect(decoded.iTermOpenMode == original.iTermOpenMode)
        #expect(decoded.vscodeOpenMode == original.vscodeOpenMode)
        #expect(decoded.lastSelectedRepositoryID == original.lastSelectedRepositoryID)
    }

    @Test func defaultsCodableRoundTrip() throws {
        let original = AppSettings()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.menuBarEnabled == true)
        #expect(decoded.iTermOpenMode == .newTab)
        #expect(decoded.vscodeOpenMode == .newWindow)
        #expect(decoded.lastSelectedRepositoryID == nil)
    }
}
