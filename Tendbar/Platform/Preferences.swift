import AppKit
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
        static let logEvents = "log.events"
        static let replyPreview = "notify.done.preview"
        static let menuBar = "view.menuBar"
        static let pill = "view.pill"
        static let pillLines = "view.pill.lines"
        static let panelPreviews = "view.panel.previews"
        static let usage = "view.panel.usage"
        static let hideFromCapture = "view.hideFromCapture"
        static let muted = "notify.muted"
        static let theme = "view.theme"
        static let soundStyle = "notify.sound.style"
        static let remindAfter = "notify.remindAfter"
        static let quietAfter = "notify.quietAfter"
        static let limitResets = "notify.limits.resets"
        static let today = "view.panel.today"
        static let permissionActions = "notify.permissionActions"
        static let nextSessionShortcut = "shortcut.nextSession"
        static let desktopBanners = "notify.desktop.leaveToApp"
        static let glowOnlyInFront = "notify.inFront.glowOnly"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onNotchViewChange: (() -> Void)?
    @ObservationIgnored var onLogEventsChange: ((Bool) -> Void)?
    @ObservationIgnored var onShortcutChange: ((NextSessionShortcut) -> Void)?

    var notifyNeedsYou: Bool { didSet { defaults.set(notifyNeedsYou, forKey: Key.needsYou) } }
    var notifyDone: Bool { didSet { defaults.set(notifyDone, forKey: Key.done) } }
    var notifyFailed: Bool { didSet { defaults.set(notifyFailed, forKey: Key.failed) } }
    /// Sessions in the Claude desktop app get its own banners, not Tendbar's.
    var leaveDesktopBanners: Bool { didSet { defaults.set(leaveDesktopBanners, forKey: Key.desktopBanners) } }
    /// A session whose tab is in front only makes the screen edge glow.
    var glowOnlyInFront: Bool { didSet { defaults.set(glowOnlyInFront, forKey: Key.glowOnlyInFront) } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Key.sound) } }
    var soundStyle: SoundStyle { didSet { defaults.set(soundStyle.rawValue, forKey: Key.soundStyle) } }
    /// Minutes a session may wait for you before a reminder; 0 turns reminders off.
    var remindAfterMinutes: Int { didSet { defaults.set(remindAfterMinutes, forKey: Key.remindAfter) } }
    /// Minutes without hook events before a working session counts as stuck; 0 turns it off.
    var quietAfterMinutes: Int { didSet { defaults.set(quietAfterMinutes, forKey: Key.quietAfter) } }
    var notifyLimitResets: Bool { didSet { defaults.set(notifyLimitResets, forKey: Key.limitResets) } }
    var panelToday: Bool { didSet { defaults.set(panelToday, forKey: Key.today) } }
    /// Allow and Deny on permission banners. Off by default: it answers a prompt without looking at the terminal.
    var permissionActions: Bool { didSet { defaults.set(permissionActions, forKey: Key.permissionActions) } }
    var edgeGlow: Bool { didSet { defaults.set(edgeGlow, forKey: Key.glow) } }
    var glowOnDone: Bool { didSet { defaults.set(glowOnDone, forKey: Key.glowDone) } }
    var showReplyPreview: Bool { didSet { defaults.set(showReplyPreview, forKey: Key.replyPreview) } }
    var notifyLimits: Bool { didSet { defaults.set(notifyLimits, forKey: Key.limits) } }
    var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: Key.menuBar) } }
    var pillVisibility: PillVisibility { didSet { defaults.set(pillVisibility.rawValue, forKey: Key.pill) } }
    var pillLimitLines: Bool { didSet { defaults.set(pillLimitLines, forKey: Key.pillLines) } }
    var panelPreviews: Bool { didSet { defaults.set(panelPreviews, forKey: Key.panelPreviews) } }
    var usageStyle: UsageStyle { didSet { defaults.set(usageStyle.rawValue, forKey: Key.usage) } }
    var logEvents: Bool {
        didSet {
            defaults.set(logEvents, forKey: Key.logEvents)
            onLogEventsChange?(logEvents)
        }
    }
    /// Keeps the pill and the glow out of screen sharing and recordings, so folder names and limits stay private.
    var hideFromCapture: Bool {
        didSet {
            defaults.set(hideFromCapture, forKey: Key.hideFromCapture)
            onNotchViewChange?()
        }
    }
    var nextSessionShortcut: NextSessionShortcut {
        didSet {
            defaults.set(nextSessionShortcut.rawValue, forKey: Key.nextSessionShortcut)
            onShortcutChange?(nextSessionShortcut)
        }
    }
    var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: Key.theme)
            theme.apply()
        }
    }
    /// Folders whose sessions never raise a banner or a glow.
    var mutedFolders: [String] { didSet { defaults.set(mutedFolders, forKey: Key.muted) } }
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
            Key.pillLines: true, Key.panelPreviews: true, Key.hideFromCapture: true,
            Key.remindAfter: 5, Key.quietAfter: 15, Key.limitResets: true, Key.today: true, Key.desktopBanners: true, Key.glowOnlyInFront: true,
        ])
        notifyNeedsYou = defaults.bool(forKey: Key.needsYou)
        notifyDone = defaults.bool(forKey: Key.done)
        notifyFailed = defaults.bool(forKey: Key.failed)
        leaveDesktopBanners = defaults.bool(forKey: Key.desktopBanners)
        glowOnlyInFront = defaults.bool(forKey: Key.glowOnlyInFront)
        playSound = defaults.bool(forKey: Key.sound)
        soundStyle = defaults.string(forKey: Key.soundStyle).flatMap(SoundStyle.init) ?? .bird
        remindAfterMinutes = defaults.integer(forKey: Key.remindAfter)
        quietAfterMinutes = defaults.integer(forKey: Key.quietAfter)
        notifyLimitResets = defaults.bool(forKey: Key.limitResets)
        panelToday = defaults.bool(forKey: Key.today)
        permissionActions = defaults.bool(forKey: Key.permissionActions)
        edgeGlow = defaults.bool(forKey: Key.glow)
        glowOnDone = defaults.bool(forKey: Key.glowDone)
        notifyLimits = defaults.bool(forKey: Key.limits)
        notchView = defaults.bool(forKey: Key.notch)
        logEvents = defaults.bool(forKey: Key.logEvents)
        showReplyPreview = defaults.bool(forKey: Key.replyPreview)
        menuBarStyle = defaults.string(forKey: Key.menuBar).flatMap(MenuBarStyle.init) ?? .waiting
        pillVisibility = defaults.string(forKey: Key.pill).flatMap(PillVisibility.init) ?? .activity
        pillLimitLines = defaults.bool(forKey: Key.pillLines)
        panelPreviews = defaults.bool(forKey: Key.panelPreviews)
        usageStyle = defaults.string(forKey: Key.usage).flatMap(UsageStyle.init) ?? .full
        hideFromCapture = defaults.bool(forKey: Key.hideFromCapture)
        mutedFolders = defaults.stringArray(forKey: Key.muted) ?? []
        theme = defaults.string(forKey: Key.theme).flatMap(Theme.init) ?? .system
        nextSessionShortcut = defaults.string(forKey: Key.nextSessionShortcut).flatMap(NextSessionShortcut.init) ?? .off
    }

    func isMuted(_ folder: String?) -> Bool {
        folder.map(mutedFolders.contains) ?? false
    }

    func setMuted(_ muted: Bool, folder: String) {
        if muted, !mutedFolders.contains(folder) {
            mutedFolders.append(folder)
        } else if !muted {
            mutedFolders.removeAll { $0 == folder }
        }
    }

    var alertSettings: AlertSettings {
        var settings = AlertSettings()
        settings.notifyNeedsYou = notifyNeedsYou
        settings.notifyDone = notifyDone
        settings.notifyFailed = notifyFailed
        settings.notifyLimits = notifyLimits
        settings.sound = playSound
        settings.birdSounds = soundStyle == .bird
        settings.remindAfter = remindAfterMinutes > 0 ? TimeInterval(remindAfterMinutes * 60) : nil
        settings.quietAfter = quietAfterMinutes > 0 ? TimeInterval(quietAfterMinutes * 60) : nil
        settings.notifyLimitResets = notifyLimitResets
        settings.answersPermissions = permissionActions
        settings.flash = edgeGlow
        settings.flashOnDone = glowOnDone
        settings.showsReplyPreview = showReplyPreview
        settings.mutedFolders = Set(mutedFolders)
        settings.leavesClaudeDesktopBanners = leaveDesktopBanners
        settings.glowOnlyInFront = glowOnlyInFront
        settings.quietForFocus = defaults.bool(forKey: FocusFilter.quietKey)
        return settings
    }
}

/// Which sound a banner plays when sounds are on.
enum SoundStyle: String, CaseIterable, Identifiable {
    case bird, system
    var id: Self { self }
}

/// What the menu bar item shows next to the bird.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case bird, waiting, limit
    var id: Self { self }
}

/// When the pill next to the notch is on screen.
enum PillVisibility: String, CaseIterable, Identifiable {
    case always, activity, needsYou
    var id: Self { self }
}

/// Light or dark for the panel and settings. The pill stays dark, since it sits on the black notch.
enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }

    @MainActor
    func apply() {
        NSApp?.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// How the panel shows each account's limits.
enum UsageStyle: String, CaseIterable, Identifiable {
    case full, compact, hidden
    var id: Self { self }
}
