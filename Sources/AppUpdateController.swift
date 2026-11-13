import AppKit
import Combine
import Sparkle

@MainActor final class AppUpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var sessionInProgress = false
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private var started = false

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.sessionInProgress).receive(on: DispatchQueue.main).assign(to: &$sessionInProgress)
    }

    func start() {
        guard !started else { return }
        started = true
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }
}
