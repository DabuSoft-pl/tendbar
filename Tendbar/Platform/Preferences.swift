import Foundation
import Observation
import TendbarApplication

/// The user's choices, stored in UserDefaults. The settings screen binds to it directly and use cases read it
/// through `AlertSettingsProviding`.
@MainActor
@Observable
final class Preferences: AlertSettingsProviding {
    private enum Key {
        static let needsYou = "notify.needsYou"
        static let done = "notify.done"
        static let failed = "notify.failed"
        static let sound = "notify.sound"
        static let glow = "notify.glow"
        static let glowDone = "notify.glow.done"
        static let notch = "view.notch"
        static let limits = "notify.limits"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onNotchViewChange: (() -> Void)?

    var notifyNeedsYou: Bool { didSet { defaults.set(notifyNeedsYou, forKey: Key.needsYou) } }
    var notifyDone: Bool { didSet { defaults.set(notifyDone, forKey: Key.done) } }
    var notifyFailed: Bool { didSet { defaults.set(notifyFailed, forKey: Key.failed) } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Key.sound) } }
    var edgeGlow: Bool { didSet { defaults.set(edgeGlow, forKey: Key.glow) } }
    var glowOnDone: Bool { didSet { defaults.set(glowOnDone, forKey: Key.glowDone) } }
    var notifyLimits: Bool { didSet { defaults.set(notifyLimits, forKey: Key.limits) } }
    var notchView: Bool {
        didSet {
            defaults.set(notchView, forKey: Key.notch)
            onNotchViewChange?()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.needsYou: true, Key.done: true, Key.failed: true, Key.sound: true, Key.glow: true, Key.glowDone: true, Key.notch: true, Key.limits: true,
        ])
        notifyNeedsYou = defaults.bool(forKey: Key.needsYou)
        notifyDone = defaults.bool(forKey: Key.done)
        notifyFailed = defaults.bool(forKey: Key.failed)
        playSound = defaults.bool(forKey: Key.sound)
        edgeGlow = defaults.bool(forKey: Key.glow)
        glowOnDone = defaults.bool(forKey: Key.glowDone)
        notifyLimits = defaults.bool(forKey: Key.limits)
        notchView = defaults.bool(forKey: Key.notch)
    }

    var alertSettings: AlertSettings {
        var settings = AlertSettings()
        settings.notifyNeedsYou = notifyNeedsYou
        settings.notifyDone = notifyDone
        settings.notifyFailed = notifyFailed
        settings.notifyLimits = notifyLimits
        settings.sound = playSound
        settings.flash = edgeGlow
        settings.flashOnDone = glowOnDone
        return settings
    }
}
