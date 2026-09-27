import AppKit
import Combine
import Sparkle
import StatsCore

@MainActor final class AppUpdater: ObservableObject {
    @Published private(set) var isConfigured = false
    @Published private(set) var isAvailable = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var status = "Updates aren’t configured for this build."
    private var controller: SPUStandardUpdaterController?
    private var observations = Set<AnyCancellable>()

    init(enabled: Bool = true, bundle: Bundle = .main) {
        guard enabled, UpdateConfiguration(
            feedURL: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        ) != nil else { return }
        isConfigured = true

        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        do {
            try updater.start()
            isAvailable = true
            status = "Check for new versions of zStats."
        } catch {
            status = "The update service couldn’t start. Reopen zStats to try again."
            NSLog("Sparkle startup failed: %@", error.localizedDescription)
            return
        }
        updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }.store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }.store(in: &observations)
        updater.publisher(for: \.lastUpdateCheckDate).receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastUpdateCheckDate = $0 }.store(in: &observations)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard isAvailable else { return }
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}
