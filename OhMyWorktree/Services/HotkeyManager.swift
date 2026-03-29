import AppKit
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.ohmyworktree", category: "HotkeyManager")

// MARK: - KeyCombo

/// Represents a keyboard shortcut combination (modifier flags + key code).
struct KeyCombo: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    /// Parses a human-readable shortcut string like "⌥⇧W" into a `KeyCombo`.
    /// Requires at least one modifier and exactly one key character at the end.
    static func from(string: String) -> KeyCombo? {
        guard !string.isEmpty else { return nil }

        var flags: NSEvent.ModifierFlags = []
        var remaining = string

        // Parse modifier symbols from the front using lookup table
        while let first = remaining.first, let modifier = modifierMap[first] {
            flags.insert(modifier)
            remaining.removeFirst()
        }

        // Must have at least one modifier and exactly one key character left
        guard !flags.isEmpty, remaining.count == 1 else { return nil }

        // Try the raw character first (for non-alpha keys like , . ⌫), then uppercased
        let keyChar = Self.keyCodeMap[remaining] != nil ? remaining : remaining.uppercased()
        guard let code = Self.keyCodeMap[keyChar] else { return nil }

        return KeyCombo(keyCode: code, modifiers: flags)
    }

    /// Returns the human-readable display string (e.g. "⌥⇧W").
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }

        for (key, code) in Self.keyCodeMap where code == keyCode {
            result += key
            break
        }
        return result
    }

    static let modifierMap: [Character: NSEvent.ModifierFlags] = [
        "⌘": .command,
        "⌥": .option,
        "⇧": .shift,
        "⌃": .control
    ]

    static let keyCodeMap: [String: UInt16] = [
        "A": UInt16(kVK_ANSI_A),
        "B": UInt16(kVK_ANSI_B),
        "C": UInt16(kVK_ANSI_C),
        "D": UInt16(kVK_ANSI_D),
        "E": UInt16(kVK_ANSI_E),
        "F": UInt16(kVK_ANSI_F),
        "G": UInt16(kVK_ANSI_G),
        "H": UInt16(kVK_ANSI_H),
        "I": UInt16(kVK_ANSI_I),
        "J": UInt16(kVK_ANSI_J),
        "K": UInt16(kVK_ANSI_K),
        "L": UInt16(kVK_ANSI_L),
        "M": UInt16(kVK_ANSI_M),
        "N": UInt16(kVK_ANSI_N),
        "O": UInt16(kVK_ANSI_O),
        "P": UInt16(kVK_ANSI_P),
        "Q": UInt16(kVK_ANSI_Q),
        "R": UInt16(kVK_ANSI_R),
        "S": UInt16(kVK_ANSI_S),
        "T": UInt16(kVK_ANSI_T),
        "U": UInt16(kVK_ANSI_U),
        "V": UInt16(kVK_ANSI_V),
        "W": UInt16(kVK_ANSI_W),
        "X": UInt16(kVK_ANSI_X),
        "Y": UInt16(kVK_ANSI_Y),
        "Z": UInt16(kVK_ANSI_Z),
        ",": UInt16(kVK_ANSI_Comma),
        ".": UInt16(kVK_ANSI_Period),
        "/": UInt16(kVK_ANSI_Slash),
        "⌫": UInt16(kVK_Delete)
    ]
}

// MARK: - HotkeyManager

/// Manages a global keyboard shortcut that triggers an action when pressed.
/// Uses `NSEvent.addGlobalMonitorForEvents` for global key detection
/// and `NSEvent.addLocalMonitorForEvents` for when the app itself is active.
@MainActor
final class HotkeyManager {

    // MARK: - Properties

    private(set) var isRegistered = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var currentCombo: KeyCombo?
    private var action: (() -> Void)?
    private var enabled = true

    // MARK: - Public API

    /// Registers a global hotkey with the given key combo string (e.g. "⌥⇧W").
    /// The `handler` closure is called on the main thread when the hotkey is pressed.
    func register(keyCombo: String, handler: @escaping () -> Void) {
        guard let combo = KeyCombo.from(string: keyCombo) else {
            logger.warning("Invalid key combo string: \(keyCombo)")
            return
        }

        // Clean up any previous registration
        unregister()

        currentCombo = combo
        action = handler
        enabled = true

        installMonitors(for: combo)
        isRegistered = true
        logger.info("Registered global hotkey: \(combo.displayString)")
    }

    /// Removes the current global hotkey registration.
    func unregister() {
        removeMonitors()
        isRegistered = false
    }

    /// Enables or disables the hotkey without losing the configured combo.
    /// When re-enabled, the previously configured combo is restored.
    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled {
            guard let combo = currentCombo else { return }
            installMonitors(for: combo)
            isRegistered = true
            logger.info("Re-enabled global hotkey: \(combo.displayString)")
        } else {
            removeMonitors()
            isRegistered = false
            logger.info("Disabled global hotkey")
        }
    }

    // MARK: - Private

    private func installMonitors(for combo: KeyCombo) {
        removeMonitors()

        let requiredModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let expectedFlags = combo.modifiers.intersection(requiredModifiers)

        // Global monitor: fires when our app is NOT the active app
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventFlags = event.modifierFlags.intersection(requiredModifiers)
            if event.keyCode == combo.keyCode && eventFlags == expectedFlags {
                DispatchQueue.main.async { [weak self] in
                    self?.action?()
                }
            }
        }

        // Local monitor: fires when our app IS the active app
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventFlags = event.modifierFlags.intersection(requiredModifiers)
            if event.keyCode == combo.keyCode && eventFlags == expectedFlags {
                DispatchQueue.main.async { [weak self] in
                    self?.action?()
                }
                return nil  // consume the event
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}
