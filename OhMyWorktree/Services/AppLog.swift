import Foundation
import os

/// Centralized logging seam. Excluded from coverage because it holds the
/// irreducible `Bundle.main.bundleIdentifier ?? …` fallback and the
/// `Logger.debug(_:)` message autoclosures (debug level is disabled in the test
/// runner, so those autoclosures never evaluate — not unit-coverable).
enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.ohmyworktree"

    static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    /// Debug log with an EAGERLY-built message (interpolated at the call site,
    /// so the call site stays covered); the `.debug` autoclosure lives here.
    static func debug(_ message: String, category: String) {
        logger(category).debug("\(message)")
    }
}
