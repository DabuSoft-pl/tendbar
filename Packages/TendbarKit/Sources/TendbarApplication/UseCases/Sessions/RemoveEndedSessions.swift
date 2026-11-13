import TendbarDomain

@MainActor
public final class RemoveEndedSessions {
    private let repository: SessionRepository
    private let output: SessionsOutput

    public init(repository: SessionRepository, output: SessionsOutput) {
        self.repository = repository
        self.output = output
    }

    public func execute() {
        var store = repository.load()
        store.removeEnded()
        repository.save(store)
        output.show(store)
    }
}
