import Foundation
import TendbarApplication
import TendbarDomain

/// Turns what the user does in the session list into use case calls.
@MainActor
final class SessionsController {
    private let model: SessionsViewModel
    private let openSession: OpenSession
    private let openNext: OpenNextSession
    private let markAllSeen: MarkAllSessionsSeen
    private let removeEnded: RemoveEndedSessions
    private let desk: PermissionDesk?

    init(
        model: SessionsViewModel,
        repository: SessionRepository,
        openSession: OpenSession,
        markAllSeen: MarkAllSessionsSeen,
        removeEnded: RemoveEndedSessions,
        desk: PermissionDesk? = nil
    ) {
        self.model = model
        self.desk = desk
        self.openSession = openSession
        openNext = OpenNextSession(repository: repository, openSession: openSession)
        self.markAllSeen = markAllSeen
        self.removeEnded = removeEnded
    }

    func select(_ session: Session) {
        open(sessionID: session.id)
    }

    func open(sessionID: String) {
        guard let outcome = openSession.execute(sessionID: sessionID) else { return }
        model.jumpMessage = Self.message(for: outcome)
    }

    /// The global shortcut. Returns false when nothing needs you, so the caller can say so.
    @discardableResult
    func openNextSession() -> Bool {
        guard let outcome = openNext.execute() else { return false }
        model.jumpMessage = Self.message(for: outcome)
        return true
    }

    /// Allow or Deny from the panel or the pill. A prompt already answered in the terminal is simply gone.
    func answer(_ ask: PermissionAsk, _ decision: PermissionDecision) {
        desk?.answer(askID: ask.id, sessionID: ask.sessionID, decision: decision)
    }

    func markAllAsRead() {
        markAllSeen.execute()
    }

    func removeEndedSessions() {
        removeEnded.execute()
    }

    func dismissJumpMessage() {
        model.jumpMessage = nil
    }

    static func message(for outcome: JumpOutcome) -> String? {
        switch outcome {
        case .jumped, .activated:
            nil
        case .notRunning:
            String(localized: "This session's terminal is not running.")
        case .unavailable:
            String(localized: "Tendbar cannot switch to this terminal yet.")
        case let .notAuthorized(app):
            String(localized: "Allow Tendbar to control \(app) in System Settings → Privacy & Security → Automation.")
        case let .failed(message):
            String(localized: "Could not switch to the session: \(message)")
        }
    }
}
