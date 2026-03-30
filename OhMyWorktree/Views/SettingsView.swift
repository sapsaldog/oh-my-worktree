import SwiftUI

struct SettingsView: View {
    var updaterManager: UpdaterManager
    var shortcutManager: ShortcutManager

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var commitHash: String {
        Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? "unknown"
    }

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsView()
            }
            Tab("Shortcuts", systemImage: "keyboard") {
                ShortcutsSettingsView(shortcutManager: shortcutManager)
            }
            Tab("Advanced", systemImage: "wrench.adjustable") {
                AdvancedSettingsView()
            }
            Tab("Updates", systemImage: "arrow.triangle.2.circlepath") {
                UpdatesSettingsView(updaterManager: updaterManager)
            }
        }
        .frame(minWidth: 450, minHeight: 350)
        .overlay(alignment: .bottom) {
            Text("v\(appVersion) (\(buildNumber)) · \(commitHash)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
    }
}
