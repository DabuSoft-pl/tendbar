import Foundation
import TendbarDomain

public enum JumpOutcome: Sendable, Equatable {
    case jumped
    case activated
    case notRunning
    case unavailable
    case notAuthorized(app: String)
    case failed(String)
}

/// Brings the terminal tab (or editor window) of a session to the front.
@MainActor
public protocol TerminalNavigating: AnyObject {
    func jump(to session: Session) -> JumpOutcome
    /// Whether the session's tab is in front and the user is at the Mac, so a glow is enough.
    func isInFront(_ session: Session) -> Bool
}

public extension TerminalNavigating {
    func isInFront(_ session: Session) -> Bool { false }
}

public enum LoginItemState: Sendable, Equatable {
    case enabled
    case requiresApproval
    case disabled
}

@MainActor
public protocol LoginItemControlling: AnyObject {
    var state: LoginItemState { get }
    func setEnabled(_ enabled: Bool) throws
}

public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Tells whether the Claude Code process behind a session still runs. Nil when it cannot tell.
public protocol SessionProcessChecking: Sendable {
    func isRunning(_ terminal: TerminalContext) -> Bool?
}
