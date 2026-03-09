import UserNotifications

// MARK: - NotificationManager

/// Posts macOS system notifications for background job completions and failures.
/// Acts as its own UNUserNotificationCenterDelegate so banners appear even while
/// the app's popover is frontmost.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

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
        }
        post(content: content, identifier: job.id.uuidString)
    }

    func notifyFailed(message: String, jobID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Oh My Worktree — Task Failed"
        content.body = message
        content.sound = .defaultCritical
        post(content: content, identifier: "fail-\(jobID.uuidString)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notification banner even when the app's popover is open.
    func userNotificationCenter(
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
