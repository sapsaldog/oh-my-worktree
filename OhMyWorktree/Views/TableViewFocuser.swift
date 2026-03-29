import SwiftUI

// MARK: - NSTableView Auto-Focus

/// Finds the NSTableView backing a SwiftUI List and makes it the first responder
/// so arrow keys and delete work without requiring a click first.
struct TableViewFocuser: NSViewRepresentable {
    let worktreeCount: Int

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard worktreeCount > 0 else { return }
        // Defer to next main actor tick to avoid layout recursion
        Task { @MainActor in
            guard let window = nsView.window,
                  let tableView = Self.findTableView(in: window.contentView)
            else { return }
            if window.firstResponder === window || window.firstResponder === window.contentView {
                window.makeFirstResponder(tableView)
            }
        }
    }

    private static func findTableView(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let tableView = view as? NSTableView { return tableView }
        for subview in view.subviews {
            if let found = findTableView(in: subview) { return found }
        }
        return nil
    }
}
