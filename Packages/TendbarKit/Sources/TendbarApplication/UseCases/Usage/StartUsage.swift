import TendbarDomain

/// Shows the readings kept from the last run and warns about limits crossed meanwhile.
@MainActor
public final class StartUsage {
    private let repository: UsageRepository
    private let output: UsageOutput
    private let checkWarnings: CheckLimitWarnings

    public init(repository: UsageRepository, output: UsageOutput, checkWarnings: CheckLimitWarnings) {
        self.repository = repository
        self.output = output
        self.checkWarnings = checkWarnings
    }

    public func execute() {
        output.show(repository.load())
        checkWarnings.execute()
    }
}
