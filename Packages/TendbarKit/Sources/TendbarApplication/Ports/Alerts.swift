import TendbarDomain

public enum FlashTone: Sendable, Equatable {
    case attention
    case success
    case failure

    public init(_ kind: AlertKind) {
        switch kind {
        case .needsYou: self = .attention
        case .done: self = .success
        case .failed: self = .failure
        }
    }
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
    public var flash = true
    public var flashOnDone = true
    /// Whether a "done" banner shows the start of Claude's reply.
    public var showsReplyPreview = false

    public init() {}

    public func notifies(_ kind: AlertKind) -> Bool {
        switch kind {
        case .needsYou: notifyNeedsYou
        case .done: notifyDone
        case .failed: notifyFailed
        }
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
    func present(_ kind: AlertKind, for session: Session, sound: Bool)
    func presentLimit(_ warning: LimitWarning, account: AccountUsage, sound: Bool)
    func dismiss(sessionID: String)
}

@MainActor
public protocol NotificationPermissions: AnyObject {
    func permission() async -> NotificationPermission
    /// Asks macOS for permission and returns the result with the error text, if any.
    func requestPermission() async -> (NotificationPermission, error: String?)
    func sendTest(sound: Bool) async throws
}

/// The glowing screen edge.
@MainActor
public protocol ScreenFlashing: AnyObject {
    func flash(_ tone: FlashTone)
}
