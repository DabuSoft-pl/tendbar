import Foundation
import TendbarApplication
import TendbarDomain

/// Turns what the user does in the session list into use case calls.
@MainActor
final class SessionsController {
    private let model: SessionsViewModel
    private let openSession: OpenSession
    private let markAllSeen: MarkAllSessionsSeen
    private let removeEnded: RemoveEndedSessions

    init(model: SessionsViewModel, openSession: OpenSession, markAllSeen: MarkAllSessionsSeen, removeEnded: RemoveEndedSessions) {
        self.model = model
        self.openSession = openSession
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
