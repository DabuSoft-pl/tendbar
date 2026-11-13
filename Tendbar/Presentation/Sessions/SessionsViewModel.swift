import Foundation
import Observation
import TendbarApplication
import TendbarDomain

/// What the session list and the notch show. Use cases push new state here through `SessionsOutput`.
@MainActor
@Observable
final class SessionsViewModel: SessionsOutput {
    private(set) var store = SessionStore()
    var jumpMessage: String?
    var listenerError: String?

    var sessions: [Session] { store.ordered }
    var needsYouCount: Int { store.needsYouCount }
    var hasUnread: Bool { store.hasUnread }

    /// Sessions worth showing in the notch: busy, waiting, failed or with an unread reply.
    var active: [Session] {
        sessions.filter { $0.state == .working || $0.state == .needsYou || $0.state == .failed || $0.unread }
    }

    func count(of state: SessionState) -> Int {
        store.count(of: state)
    }

    func show(_ sessions: SessionStore) {
        store = sessions
    }
}
