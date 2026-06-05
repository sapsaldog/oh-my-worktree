import SwiftUI

// Presentation helpers mapping a Worktree's state to the prototype's status dot
// color and label. `isRoot` is supplied by the caller (needs the repository).
extension Worktree {

    func statusColor(isRoot: Bool) -> Color {
        if isBare { return OMWColor.sysGray }
        if isDetached { return OMWColor.sysYellow }
        if isLocked { return OMWColor.sysOrange }
        return OMWColor.sysGreen   // root or active
    }

    func statusLabel(isRoot: Bool) -> String {
        if isBare { return "Bare" }
        if isDetached { return "Detached HEAD" }
        if isLocked { return "Locked" }
        if isRoot { return "Main worktree" }
        return "Active"
    }
}
