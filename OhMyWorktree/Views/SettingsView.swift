import SwiftUI

struct SettingsView: View {
    @ObservedObject var updaterManager: UpdaterManager
    @ObservedObject var shortcutManager: ShortcutManager

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
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            ShortcutsSettingsView(shortcutManager: shortcutManager)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "wrench.adjustable") }

            UpdatesSettingsView(updaterManager: updaterManager)
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(minWidth: 450, minHeight: 350)
        .overlay(alignment: .bottom) {
            Text("v\(appVersion) (\(buildNumber)) · \(commitHash)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
    }
}
