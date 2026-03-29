import AppKit
import SwiftUI

// MARK: - Key Recording NSView Bridge

/// An NSViewRepresentable that captures raw key events during recording mode.
struct KeyRecordingField: NSViewRepresentable {
    let viewModel: HotkeyRecorderViewModel

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyEvent = { [weak viewModel] keyCode, modifiers in
            MainActor.assumeIsolated {
                _ = viewModel?.handleKey(keyCode: keyCode, modifiers: modifiers)
            }
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {}
}

/// A custom NSView that becomes first responder to capture key events.
final class KeyCaptureView: NSView {
    var onKeyEvent: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        onKeyEvent?(event.keyCode, event.modifierFlags)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw the placeholder text
        let text = "Type shortcut..."
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        text.draw(in: dirtyRect, withAttributes: attributes)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 120, height: 20)
    }
}
