import TendbarDomain

/// Opens the session that needs you most, for the global shortcut.
@MainActor
public final class OpenNextSession {
    private let repository: SessionRepository
    private let openSession: OpenSession

    public init(repository: SessionRepository, openSession: OpenSession) {
        self.repository = repository
        self.openSession = openSession
    }

    /// Returns nil when no session waits for you or has news.
    @discardableResult
    public func execute() -> JumpOutcome? {
        guard let next = repository.load().nextForYou else { return nil }
        return openSession.execute(sessionID: next.id)
    }
}
