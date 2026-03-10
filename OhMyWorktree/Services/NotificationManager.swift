import UserNotifications

// MARK: - NotificationManager

/// Posts macOS system notifications for background job completions and failures.
/// Acts as its own UNUserNotificationCenterDelegate so banners appear even while
/// the app's popover is frontmost.
///
/// Fix 7: @MainActor replaces @unchecked Sendable — all notification calls originate
/// from MainActor contexts (WorktreeListViewModel), so making the class MainActor-isolated
/// gives the compiler proper thread-safety guarantees without bypassing checks.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyCompleted(job: BackgroundJob) {
        let content = UNMutableNotificationContent()
        content.title = "Oh My Worktree"
        switch job.kind {
        case .removeWorktree:
            content.body = "'\(job.displayName)' removed"
        case .pull:
            content.body = "'\(job.displayName)' pulled successfully"
        case .addWorktreeFromPR:
            content.body = "'\(job.displayName)' imported successfully"
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
