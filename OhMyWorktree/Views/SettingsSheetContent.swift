import AppKit
import KeyboardShortcuts
import os
import ServiceManagement
import SwiftUI

private let settingsLogger = Logger(subsystem: "com.ohmyworktree", category: "Settings")

/// Glass Settings sheet matching the Tahoe prototype: a segmented control
/// (General / Appearance / Shortcuts / Updates) over grouped rows, with a Done pill.
struct SettingsSheetContent: View {
    var updaterManager: UpdaterManager
    var store: ShortcutStore
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("accentColorName") private var accentColorName = AccentChoice.default.rawValue
    @State private var tab = Tab.general

    private enum Tab: String, CaseIterable {
        case general = "General"
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"
        case updates = "Updates"
    }

    private var accent: Color { AccentChoice.named(accentColorName).color }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 16, weight: .bold)).foregroundStyle(OMWColor.labelPrimary)
                Spacer()
            }
            .padding(.init(top: 18, leading: 20, bottom: 12, trailing: 20))

            segmented.padding(.bottom, 14)

            ScrollView {
                tabContent
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { close() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.init(top: 12, leading: 20, bottom: 16, trailing: 20))
        }
        .frame(width: 480, height: 540)
        // Liquid Glass: a thin behind-window material so the worktree window reads
        // through. See project_glass_sheets_need_presentationbackground.
        .glassSheet()
        .tint(accent)
        .environment(\.omwAccent, accent)
    }

    private func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .general: GeneralTab()
        case .appearance: AppearanceTab(accentColorName: $accentColorName)
        case .shortcuts: ShortcutsTab(store: store)
        case .updates: UpdatesTab(updaterManager: updaterManager)
        }
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tab == item ? OMWColor.labelPrimary : OMWColor.labelSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(tab == item ? AnyShapeStyle(OMWColor.controlBg) : AnyShapeStyle(Color.clear),
                                   in: RoundedRectangle(cornerRadius: 6))
                        .shadow(color: tab == item ? .black.opacity(0.12) : .clear, radius: 1, y: 0.5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(OMWColor.fillTertiary, in: RoundedRectangle(cornerRadius: OMWRadius.md))
    }
}

// MARK: - Reusable glass settings pieces

/// A grouped glass card (`.set-section`) that hairline-separates its rows.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(OMWColor.bgRaised, in: RoundedRectangle(cornerRadius: OMWRadius.md))
            .overlay(RoundedRectangle(cornerRadius: OMWRadius.md).strokeBorder(OMWColor.separator, lineWidth: 0.5))
    }
}

/// One settings row: optional leading icon, title + subtitle, trailing control.
struct SettingsRow<Trailing: View>: View {
    var icon: String?
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(OMWColor.labelSecondary).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(OMWColor.labelPrimary)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(OMWColor.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

func settingsHairline() -> some View {
    Rectangle().fill(OMWColor.separator).frame(height: 0.5).padding(.leading, 14)
}

// MARK: - General

private struct GeneralTab: View {
    @AppStorage("copyEnvFilesEnabled") private var copyEnvFilesEnabled = true
    @AppStorage(DockPolicy.defaultsKey) private var showInDock = false
    @AppStorage(MenuBarTitle.showWorktreeNameKey) private var showWorktreeName = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var installedDiffTools: [DiffTool] = []

    var body: some View {
        SettingsCard {
            SettingsRow(icon: "arrow.left.arrow.right", title: "Diff tool",
                        subtitle: "Open copied-file diffs in this tool") {
                DiffToolMenu(available: installedDiffTools)
            }
            settingsHairline()
            SettingsRow(icon: "doc.on.doc", title: "Copy files to new worktrees",
                        subtitle: "Use .worktreeinclude patterns when creating worktrees") {
                Toggle("Copy files to new worktrees", isOn: $copyEnvFilesEnabled).toggleStyle(.omwSwitch)
            }
            settingsHairline()
            SettingsRow(icon: "power", title: "Launch at Login",
                        subtitle: "Start Oh My Worktree automatically when you log in") {
                Toggle("Launch at Login", isOn: $launchAtLogin).toggleStyle(.omwSwitch)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
            }
            settingsHairline()
            SettingsRow(icon: "dock.rectangle", title: "Show icon in Dock",
                        subtitle: "Keep the app icon in the Dock even when no window is open") {
                Toggle("Show icon in Dock", isOn: $showInDock).toggleStyle(.omwSwitch)
                    .onChange(of: showInDock) { _, _ in
                        NotificationCenter.default.post(name: .showInDockSettingChanged, object: nil)
                    }
            }
            settingsHairline()
            SettingsRow(icon: "menubar.rectangle", title: "Show worktree name in menu bar",
                        subtitle: "Display the repository and worktree next to the menu bar icon") {
                Toggle("Show worktree name in menu bar", isOn: $showWorktreeName).toggleStyle(.omwSwitch)
                    .onChange(of: showWorktreeName) { _, _ in
                        NotificationCenter.default.post(name: .menuBarTitleSettingChanged, object: nil)
                    }
            }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            installedDiffTools = DiffToolLauncher().installedTools()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            settingsLogger.error("Failed to set launch at login: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @Binding var accentColorName: String
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.default.rawValue

    private var mode: AppearanceMode { AppearanceMode.named(appearanceModeRaw) }
    private var accent: AccentChoice { AccentChoice.named(accentColorName) }

    var body: some View {
        VStack(spacing: 10) {
            SettingsCard {
                SettingsRow(icon: "circle.lefthalf.filled", title: "Appearance", subtitle: appearanceSubtitle) {
                    appearanceSegment
                }
                settingsHairline()
                SettingsRow(icon: "paintpalette", title: "Accent color", subtitle: "Tints selection, switches, and focus") {
                    accentDots
                }
            }
            Text("\(accent.rawValue) · \(mode.rawValue.capitalized)")
                .font(.system(size: 11))
                .foregroundStyle(OMWColor.labelTertiary)
                .frame(maxWidth: .infinity)
        }
        .onChange(of: appearanceModeRaw) { _, _ in NSApp.appearance = mode.nsAppearance }
        .onAppear { NSApp.appearance = mode.nsAppearance }
    }

    private var appearanceSubtitle: String {
        switch mode {
        case .auto: "Auto — follows your macOS system setting"
        case .light: "Light window chrome"
        case .dark: "Dark window chrome"
        }
    }

    private var appearanceSegment: some View {
        HStack(spacing: 2) {
            segButton("Auto", "circle.lefthalf.filled", .auto)
            segButton("Light", "sun.max", .light)
            segButton("Dark", "moon", .dark)
        }
        .padding(2)
        .background(OMWColor.fillTertiary, in: RoundedRectangle(cornerRadius: OMWRadius.sm))
    }

    private func segButton(_ label: String, _ icon: String, _ value: AppearanceMode) -> some View {
        let selected = mode == value
        return Button { appearanceModeRaw = value.rawValue } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(selected ? OMWColor.labelPrimary : OMWColor.labelSecondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(selected ? AnyShapeStyle(OMWColor.controlBg) : AnyShapeStyle(Color.clear),
                       in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private var accentDots: some View {
        HStack(spacing: 8) {
            ForEach(AccentChoice.allCases) { choice in
                Button { accentColorName = choice.rawValue } label: {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 20, height: 20)
                        .overlay {
                            if choice == accent {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            }
                        }
                        .overlay {
                            if choice == accent {
                                Circle().strokeBorder(choice.color, lineWidth: 2).padding(-3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(choice.rawValue)
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    var store: ShortcutStore
    @AppStorage("globalHotkeyEnabled") private var globalHotkeyEnabled = true

    private static let inAppActions = ShortcutAction.allCases.filter { !$0.isGlobal }

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = store.version
        VStack(spacing: 12) {
            SettingsCard {
                SettingsRow(icon: "globe", title: "Enable global hotkey",
                            subtitle: "Toggle the menu bar popup from anywhere") {
                    Toggle("Enable global hotkey", isOn: $globalHotkeyEnabled).toggleStyle(.omwSwitch)
                        .onChange(of: globalHotkeyEnabled) { _, on in
                            on ? KeyboardShortcuts.enable(.toggleMenuBarPopup) : KeyboardShortcuts.disable(.toggleMenuBarPopup)
                        }
                }
                settingsHairline()
                SettingsRow(icon: "command", title: "Toggle Menu Bar Popup", subtitle: nil) {
                    KeyboardShortcuts.Recorder("", name: .toggleMenuBarPopup)
                }
            }

            SettingsCard {
                ForEach(Array(Self.inAppActions.enumerated()), id: \.element) { index, action in
                    if index > 0 { settingsHairline() }
                    shortcutRow(action)
                }
            }

            Button("Reset All to Defaults") { store.resetInAppToDefaults() }
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func shortcutRow(_ action: ShortcutAction) -> some View {
        let conflict = store.conflictingAction(with: action).map { "Conflicts with \"\($0.displayName)\"" }
        SettingsRow(icon: nil, title: action.displayName, subtitle: conflict) {
            KeyboardShortcuts.Recorder("", name: action.name, onChange: { _ in store.noteChange() })
        }
    }
}

// MARK: - Updates

private struct UpdatesTab: View {
    var updaterManager: UpdaterManager

    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard {
                SettingsRow(icon: "arrow.triangle.2.circlepath", title: "Automatically check for updates",
                            subtitle: "Powered by Sparkle") {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updaterManager.automaticallyChecksForUpdates },
                        set: { updaterManager.automaticallyChecksForUpdates = $0 }
                    ))
                    .toggleStyle(.omwSwitch)
                }
            }
            VStack(spacing: 6) {
                Text("Oh My Worktree \(appVersion)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OMWColor.labelPrimary)
                Button { updaterManager.checkForUpdates() } label: {
                    Label("Check Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.small)
                .disabled(!updaterManager.canCheckForUpdates)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
