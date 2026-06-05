import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    var store: ShortcutStore
    @AppStorage("globalHotkeyEnabled") private var globalHotkeyEnabled = true

    var body: some View {
        Form {
            Section("Global Hotkey") {
                Toggle("Enable global hotkey", isOn: $globalHotkeyEnabled)
                    .onChange(of: globalHotkeyEnabled) { _, enabled in
                        if enabled {
                            KeyboardShortcuts.enable(.toggleMenuBarPopup)
                        } else {
                            KeyboardShortcuts.disable(.toggleMenuBarPopup)
                        }
                    }

                KeyboardShortcuts.Recorder("Toggle Menu Bar Popup:", name: .toggleMenuBarPopup)

                Text("Press the global hotkey to toggle the menu bar popup from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("In-App Shortcuts") {
                ForEach(Self.inAppActions, id: \.self) { action in
                    inAppRecorder(for: action)
                }
            }

            Section {
                Button("Reset All to Defaults") {
                    store.resetInAppToDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func inAppRecorder(for action: ShortcutAction) -> some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = store.version
        VStack(alignment: .leading, spacing: 2) {
            KeyboardShortcuts.Recorder(
                action.displayName,
                name: action.name,
                onChange: { _ in store.noteChange() }
            )
            if let conflict = store.conflictingAction(with: action) {
                Text("Conflicts with \"\(conflict.displayName)\"")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private static let inAppActions = ShortcutAction.allCases.filter { !$0.isGlobal }
}
