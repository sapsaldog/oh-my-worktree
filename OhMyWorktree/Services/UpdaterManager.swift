import AppKit
import Combine
import Foundation
import Observation
import Sparkle

@Observable
@MainActor
final class UpdaterManager {
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    var canCheckForUpdates = false
    @ObservationIgnored private var cancellable: AnyCancellable?
    @ObservationIgnored private var sessionDelegate: UpdaterSessionDelegate?

    init() {
        let sessionDelegate = UpdaterSessionDelegate {
            // The update cycle is over (update installed/dismissed, no update
            // found and alert acknowledged, error shown, or check cancelled).
            Self.postUpdaterSessionState(active: false)
        }
        self.sessionDelegate = sessionDelegate
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: sessionDelegate,
            userDriverDelegate: nil
        )
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    /// Starts a user-initiated update check.
    ///
    /// The app is a menu-bar accessory while no window is open, so before
    /// handing off to Sparkle this flags the session as active (which flips the
    /// activation policy to `.regular` via `WindowObserver`) and activates the
    /// app. Both must happen here, inside the user's click event, because
    /// macOS 14+ cooperative activation only honors requests tied to a recent
    /// user interaction — Sparkle's own later activation attempt is not enough,
    /// and without this its windows and alerts open behind other apps.
    func checkForUpdates() {
        Self.postUpdaterSessionState(active: true)
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    private static func postUpdaterSessionState(active: Bool) {
        NotificationCenter.default.post(
            name: .updaterSessionStateChanged,
            object: nil,
            userInfo: [DockPolicy.updaterSessionActiveKey: active]
        )
    }
}

/// Sparkle delegate that reports when an update cycle finishes. Kept separate
/// from `UpdaterManager` so the manager stays a plain observable class; Sparkle
/// holds its delegate weakly, so the manager retains this object.
private final class UpdaterSessionDelegate: NSObject, SPUUpdaterDelegate {
    private let onUpdateCycleFinished: @MainActor () -> Void

    init(onUpdateCycleFinished: @escaping @MainActor () -> Void) {
        self.onUpdateCycleFinished = onUpdateCycleFinished
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        // Sparkle invokes updater delegate callbacks on the main thread.
        MainActor.assumeIsolated {
            onUpdateCycleFinished()
        }
    }
}

extension Notification.Name {
    /// Posted when a user-initiated Sparkle update session starts or ends, with
    /// the state under `DockPolicy.updaterSessionActiveKey`. `WindowObserver`
    /// keeps the app `.regular` while a session is active so Sparkle's modal
    /// result alerts stay visible in front.
    static let updaterSessionStateChanged = Notification.Name("com.ohmyworktree.updaterSessionStateChanged")
}
