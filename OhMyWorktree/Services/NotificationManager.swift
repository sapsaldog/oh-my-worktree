import os
import UserNotifications

// MARK: - NotificationManager

/// Posts macOS system notifications for background job completions and failures.
/// Acts as its own UNUserNotificationCenterDelegate so banners appear even while
/// the app's popover is frontmost.
///
/// @MainActor because all call sites (WorktreeListViewModel callbacks) are MainActor-isolated.
/// `static let shared` is safe because the first access always happens from a MainActor
/// context (WorktreeListViewModel.init); if a future call site is off-MainActor, the
/// compiler will flag it.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ohmyworktree",
        category: "NotificationManager"
    )

    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Self.logger.error("Authorization error: \(error.localizedDescription)")
            } else if !granted {
                Self.logger.info("Notification permission denied by user")
            }
        }
    }

    func notifyCompleted(job: BackgroundJob) {
        let content = UNMutableNotificationContent()
        content.title = "Oh My Worktree"
        switch job.kind {
        case .removeWorktree:
            content.body = "'\(job.displayName)' removed"
        case .pull:
            content.body = "'\(job.displayName)' pulled successfully"
        case .addWorktreeFromPR(_, _, let prNumber):
            content.body = "PR #\(prNumber) imported successfully"
        }
        post(content: content, identifier: job.id.uuidString)
    }

    /// Maximum body length for failure banners — prevents oversized banners
    /// from malformed or excessively long git error output.
    private static let maxBodyLength = 200

    func notifyFailed(message: String, jobID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Oh My Worktree — Task Failed"
        content.body = String(message.prefix(Self.maxBodyLength))
        content.sound = .defaultCritical
        post(content: content, identifier: "fail-\(jobID.uuidString)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notification banner even when the app's popover is open.
    /// nonisolated so the system can invoke this delegate method from any thread
    /// without needing to dispatch to the MainActor first.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Private

    private func post(content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
