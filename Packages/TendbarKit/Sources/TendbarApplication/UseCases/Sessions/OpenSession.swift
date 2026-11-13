import TendbarDomain

/// Marks a session as read and switches to its terminal tab.
@MainActor
public final class OpenSession {
    private let repository: SessionRepository
    private let output: SessionsOutput
    private let alerts: AlertPresenting
    private let navigator: TerminalNavigating

    public init(repository: SessionRepository, output: SessionsOutput, alerts: AlertPresenting, navigator: TerminalNavigating) {
        self.repository = repository
        self.output = output
        self.alerts = alerts
        self.navigator = navigator
    }

    /// Returns nil when the session is no longer known.
    @discardableResult
    public func execute(sessionID: String) -> JumpOutcome? {
        var store = repository.load()
        guard let session = store.sessions[sessionID] else { return nil }
        store.markSeen(sessionID)
        alerts.dismiss(sessionID: sessionID)
        repository.save(store)
        output.show(store)
        return navigator.jump(to: session.terminal)
    }
}
