import Foundation

// MARK: - Protocol

/// Abstraction for crash reporting and error tracking.
/// Enables dependency injection and testability via mock implementations.
protocol CrashReporter {
    /// Initialize the crash reporter with the given DSN.
    func start(dsn: String)

    /// Capture an error with optional contextual metadata.
    func capture(error: Error, context: [String: Any])

    /// Add a breadcrumb for navigation/audit trail.
    func addBreadcrumb(message: String, category: String)
}

// MARK: - Configuration

struct CrashReporterConfiguration {
    let dsn: String

    /// Default configuration using a placeholder DSN.
    /// Replace with a real DSN before production use.
    static let `default` = CrashReporterConfiguration(
        dsn: "https://examplePublicKey@o0.ingest.sentry.io/0"
    )

    /// Reads DSN from the `SENTRY_DSN` environment variable,
    /// falling back to the default placeholder if not set.
    static func fromEnvironment() -> CrashReporterConfiguration {
        if let envDSN = ProcessInfo.processInfo.environment["SENTRY_DSN"],
           !envDSN.isEmpty {
            return CrashReporterConfiguration(dsn: envDSN)
        }
        return .default
    }
}

// MARK: - Sentry Implementation

import Sentry

/// Production crash reporter backed by the Sentry SDK.
final class SentryCrashReporter: CrashReporter {

    func start(dsn: String) {
        SentrySDK.start { options in
            options.dsn = dsn
            options.enableAutoSessionTracking = true
            options.enableCrashHandler = true
            // Attach stack traces to captured errors for richer diagnostics.
            options.attachStacktrace = true
            #if DEBUG
            options.debug = true
            options.environment = "development"
            #else
            options.environment = "production"
            #endif
        }
    }

    func capture(error: Error, context: [String: Any]) {
        SentrySDK.capture(error: error) { scope in
            for (key, value) in context {
                scope.setExtra(value: value, key: key)
            }
        }
    }

    func addBreadcrumb(message: String, category: String) {
        let crumb = Breadcrumb(level: .info, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }
}

// MARK: - No-Op Implementation

/// A crash reporter that does nothing. Useful as a default when
/// crash reporting is not configured or during testing.
final class NoOpCrashReporter: CrashReporter {
    func start(dsn: String) {}
    func capture(error: Error, context: [String: Any]) {}
    func addBreadcrumb(message: String, category: String) {}
}

// MARK: - Global Provider

/// Thread-safe global provider for the crash reporter instance.
/// Avoids circular static initialization between `OhMyWorktreeApp` and `RepositoryStore`.
enum CrashReporterProvider {
    /// The app-wide crash reporter. Defaults to `SentryCrashReporter`.
    /// Set early in the app lifecycle (e.g., from `OhMyWorktreeApp.init`).
    static var shared: CrashReporter = SentryCrashReporter()
}
