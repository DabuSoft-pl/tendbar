import TendbarDomain

/// Files a status line reading under the account signed in at the time.
@MainActor
public final class RecordUsageReading {
    private let repository: UsageRepository
    private let output: UsageOutput
    private let emails: AccountEmailResolving
    private let checkWarnings: CheckLimitWarnings

    public init(repository: UsageRepository, output: UsageOutput, emails: AccountEmailResolving, checkWarnings: CheckLimitWarnings) {
        self.repository = repository
        self.output = output
        self.emails = emails
        self.checkWarnings = checkWarnings
    }

    public func execute(_ reading: UsageReading) {
        var store = repository.load()
        guard store.record(reading, email: emails.email(configDirectory: reading.configDirectory)) else { return }
        repository.save(store)
        output.show(store)
        checkWarnings.execute()
    }
}
