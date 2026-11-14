import AppKit
import Observation
import Sparkle

/// Updates through Sparkle: the app's only network use. Sparkle asks once whether to check by itself, and Settings →
/// General can change that later. It reads the feed on GitHub and sends no system profile.
@MainActor
@Observable
final class SoftwareUpdate {
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private let reminders = GentleReminders()
    @ObservationIgnored private let channels = Channels()
    @ObservationIgnored private var checksObservation: NSKeyValueObservation?

    /// False in previews and screenshots, where nothing should reach the network.
    var isAvailable: Bool {
        controller != nil
    }

    var checksAutomatically: Bool {
        didSet {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != checksAutomatically else { return }
            updater.automaticallyChecksForUpdates = checksAutomatically
        }
    }

    /// Betas are published as pre-releases and listed in the same feed on the `beta` channel, which only a copy with
    /// this setting on looks at. Turning it off keeps the beta installed until a newer release comes out.
    var receivesBetas: Bool {
        didSet { channels.receivesBetas = receivesBetas }
    }

    /// The version a scheduled check found. Sparkle puts its window behind other apps, since Tendbar is never in
    /// front, so the panel offers it until the user looks at it.
    private(set) var waitingVersion: String?

    init(starting: Bool) {
        receivesBetas = channels.receivesBetas
        guard starting else {
            controller = nil
            checksAutomatically = false
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: channels, userDriverDelegate: reminders)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        reminders.onChange = { [weak self] version in self?.waitingVersion = version }
        // Sparkle's own first-launch question changes this setting too.
        checksObservation = controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                guard let self, self.checksAutomatically != updater.automaticallyChecksForUpdates else { return }
                self.checksAutomatically = updater.automaticallyChecksForUpdates
            }
        }
    }

    /// Checks, or brings a found update's window forward.
    func checkNow() {
        // A menu bar app is never frontmost on its own, and Sparkle's window would open behind the current app.
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

/// Lets Sparkle see beta items in the feed when the user asked for them. Copies without this delegate, such as
/// releases before betas existed, never see them.
@MainActor
private final class Channels: NSObject, @preconcurrency SPUUpdaterDelegate {
    private static let key = "updates.beta"

    var receivesBetas: Bool {
        get { UserDefaults.standard.bool(forKey: Self.key) }
        set { UserDefaults.standard.set(newValue, forKey: Self.key) }
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        receivesBetas ? ["beta"] : []
    }
}

/// Notes an update a scheduled check found, until the user gives it attention or the session ends.
@MainActor
private final class GentleReminders: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    var onChange: ((String?) -> Void)?

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !state.userInitiated { onChange?(update.displayVersionString) }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onChange?(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        onChange?(nil)
    }
}
