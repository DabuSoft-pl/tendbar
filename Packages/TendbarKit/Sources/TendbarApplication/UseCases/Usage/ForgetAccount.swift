import TendbarDomain

@MainActor
public final class ForgetAccount {
    private let repository: UsageRepository
    private let output: UsageOutput

    public init(repository: UsageRepository, output: UsageOutput) {
        self.repository = repository
        self.output = output
    }

    public func execute(accountID: String) {
        var store = repository.load()
        store.remove(accountID)
        repository.save(store)
        output.show(store)
    }
}
