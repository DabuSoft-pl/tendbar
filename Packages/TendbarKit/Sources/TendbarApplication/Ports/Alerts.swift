import Foundation
import TendbarDomain

public enum FlashTone: Sendable, Equatable {
    case attention
    case success
    case failure

    public init(_ kind: AlertKind) {
        switch kind {
        case .needsYou, .reminder, .quiet: self = .attention
        case .done: self = .success
        case .failed: self = .failure
        }
    }
}

/// What a banner sounds like.
public enum AlertSound: Sendable, Equatable {
    case none
    case system
    /// Tendbar's own short bird calls, one per kind of alert.
    case bird
}

public enum NotificationPermission: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

/// What the user chose to be told about. Read by use cases, owned by the settings screen.
public struct AlertSettings: Sendable, Equatable {
    public var notifyNeedsYou = true
    public var notifyDone = true
    public var notifyFailed = true
    public var notifyLimits = true
    public var sound = true
    public var birdSounds = true
    /// Remind about a wait after this long; nil turns reminders off.
    public var remindAfter: TimeInterval? = 5 * 60
    /// Flag a working session with no events for this long; nil turns it off.
    public var quietAfter: TimeInterval? = 15 * 60
    /// Tell when a limit that warned before has reset.
    public var notifyLimitResets = true
    /// Put Allow and Deny on the banner of a permission prompt. Off unless the user turns it on.
    public var answersPermissions = false
    public var flash = true
    public var flashOnDone = true
    /// Whether a "done" banner shows the start of Claude's reply.
    public var showsReplyPreview = false
    /// Folders (session working directories) whose sessions stay quiet.
    public var mutedFolders: Set<String> = []

    public init() {}

    public func notifies(_ kind: AlertKind) -> Bool {
        switch kind {
        case .needsYou: notifyNeedsYou
        case .done: notifyDone
        case .failed: notifyFailed
        case .reminder: notifyNeedsYou && remindAfter != nil
        case .quiet: quietAfter != nil
        }
    }

    public var alertSound: AlertSound {
        sound ? (birdSounds ? .bird : .system) : .none
    }

    public func mutes(_ session: Session) -> Bool {
        session.cwd.map(mutedFolders.contains) ?? false
    }

    public func flashes(_ kind: AlertKind) -> Bool {
        flash && (kind != .done || flashOnDone)
    }
}

@MainActor
public protocol AlertSettingsProviding: AnyObject {
    var alertSettings: AlertSettings { get }
}

/// Banners in Notification Center.
@MainActor
public protocol AlertPresenting: AnyObject {
    func present(_ kind: AlertKind, for session: Session, sound: AlertSound)
    func presentLimit(_ warning: LimitWarning, account: AccountUsage, sound: AlertSound)
    func presentLimitReset(_ reset: LimitReset, account: AccountUsage, sound: AlertSound)
    /// A "waiting for you" banner with Allow and Deny for this prompt.
    func presentPermission(_ ask: PermissionAsk, for session: Session, sound: AlertSound)
    func dismiss(sessionID: String)
}

@MainActor
public protocol NotificationPermissions: AnyObject {
    func permission() async -> NotificationPermission
    /// Asks macOS for permission and returns the result with the error text, if any.
    func requestPermission() async -> (NotificationPermission, error: String?)
    func sendTest(sound: AlertSound) async throws
}

/// The way back to a hook that waits for an answer. Sending nil lets the terminal prompt decide.
public protocol PermissionReply: AnyObject, Sendable {
    func send(_ decision: PermissionDecision?)
}

/// The glowing screen edge.
@MainActor
public protocol ScreenFlashing: AnyObject {
    func flash(_ tone: FlashTone)
}
