import Foundation
import Observation
import ServiceManagement
import TendbarKit

@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let needsYou = "notify.needsYou"
        static let done = "notify.done"
        static let failed = "notify.failed"
        static let sound = "notify.sound"
        static let glow = "notify.glow"
        static let notch = "view.notch"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var notifyNeedsYou: Bool { didSet { defaults.set(notifyNeedsYou, forKey: Key.needsYou) } }
    var notifyDone: Bool { didSet { defaults.set(notifyDone, forKey: Key.done) } }
    var notifyFailed: Bool { didSet { defaults.set(notifyFailed, forKey: Key.failed) } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Key.sound) } }
    var edgeGlow: Bool { didSet { defaults.set(edgeGlow, forKey: Key.glow) } }
    var notchView: Bool { didSet { defaults.set(notchView, forKey: Key.notch) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.needsYou: true, Key.done: true, Key.failed: true, Key.sound: true, Key.glow: true, Key.notch: true,
        ])
        edgeGlow = defaults.bool(forKey: Key.glow)
        notchView = defaults.bool(forKey: Key.notch)
        notifyNeedsYou = defaults.bool(forKey: Key.needsYou)
        notifyDone = defaults.bool(forKey: Key.done)
        notifyFailed = defaults.bool(forKey: Key.failed)
        playSound = defaults.bool(forKey: Key.sound)
    }

    func isEnabled(_ kind: AlertKind) -> Bool {
        switch kind {
        case .needsYou: notifyNeedsYou
        case .done: notifyDone
        case .failed: notifyFailed
        }
    }
}

enum LaunchAtLogin {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
