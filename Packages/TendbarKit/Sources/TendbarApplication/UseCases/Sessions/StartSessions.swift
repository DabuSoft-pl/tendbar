import TendbarDomain

/// Loads the sessions kept from the last run and drops the stale ones.
@MainActor
public final class StartSessions {
    private let repository: SessionRepository
    private let output: SessionsOutput
    private let clock: Clock

    public init(repository: SessionRepository, output: SessionsOutput, clock: Clock) {
        self.repository = repository
        self.output = output
        self.clock = clock
    }

    public func execute() {
        var store = repository.load()
        store.prune(now: clock.now())
        repository.save(store)
        output.show(store)
    }
}
