import TendbarDomain

@MainActor
public final class MarkAllSessionsSeen {
    private let repository: SessionRepository
    private let output: SessionsOutput
    private let alerts: AlertPresenting

    public init(repository: SessionRepository, output: SessionsOutput, alerts: AlertPresenting) {
        self.repository = repository
        self.output = output
        self.alerts = alerts
    }

    public func execute() {
        var store = repository.load()
        for session in store.sessions.values where session.unread { alerts.dismiss(sessionID: session.id) }
        store.markAllSeen()
        repository.save(store)
        output.show(store)
    }
}
