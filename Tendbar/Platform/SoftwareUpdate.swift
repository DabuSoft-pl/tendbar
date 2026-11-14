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

    /// False in previews and screenshots, where nothing should reach the network.
    var isAvailable: Bool {
        controller != nil
    }

    var checksAutomatically: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    init(starting: Bool) {
        if starting {
            let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: reminders)
            self.controller = controller
            checksAutomatically = controller.updater.automaticallyChecksForUpdates
        } else {
            controller = nil
            checksAutomatically = false
        }
    }

    func checkNow() {
        // A menu bar app is never frontmost on its own, and Sparkle's window would open behind the current app.
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

/// Tendbar lives in the menu bar, so a found update waits in Sparkle's window without taking the focus.
private final class GentleReminders: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }
}
