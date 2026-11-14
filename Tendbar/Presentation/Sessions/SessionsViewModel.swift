import Foundation
import Observation
import TendbarApplication
import TendbarDomain

/// What the session list and the notch show. Use cases push new state here through `SessionsOutput`, and the
/// permission prompts waiting for Allow or Deny through `PermissionsOutput`.
@MainActor
@Observable
final class SessionsViewModel: SessionsOutput, PermissionsOutput {
    private(set) var store = SessionStore()
    private(set) var asks: [String: PermissionAsk] = [:]
    var jumpMessage: String?
    var listenerError: String?

    var sessions: [Session] { store.ordered }
    var needsYouCount: Int { store.needsYouCount }
    var hasUnread: Bool { store.hasUnread }

    /// Sessions worth showing in the notch: busy, waiting, or with an unread reply or error. A read error drops out.
    var active: [Session] {
        sessions.filter { $0.state == .working || $0.state == .needsYou || $0.unread }
    }

    func count(of state: SessionState) -> Int {
        store.count(of: state)
    }

    /// The prompt this session waits on, when Tendbar may answer it.
    func ask(for session: Session) -> PermissionAsk? {
        session.state == .needsYou ? asks[session.id] : nil
    }

    func show(_ sessions: SessionStore) {
        store = sessions
    }

    func show(_ asks: [PermissionAsk]) {
        self.asks = Dictionary(asks.map { ($0.sessionID, $0) }, uniquingKeysWith: { _, last in last })
    }
}
