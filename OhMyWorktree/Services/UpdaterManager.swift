import Combine
import Foundation
import Observation
import Sparkle

@Observable
@MainActor
final class UpdaterManager {
    private let controller: SPUStandardUpdaterController
    var canCheckForUpdates = false
    @ObservationIgnored private var cancellable: AnyCancellable?

    init() {
        let startUpdater = !AppDelegate.isRunningTests
        controller = SPUStandardUpdaterController(
            startingUpdater: startUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        if startUpdater {
            cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
                .sink { [weak self] value in
                    self?.canCheckForUpdates = value
                }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }
}
