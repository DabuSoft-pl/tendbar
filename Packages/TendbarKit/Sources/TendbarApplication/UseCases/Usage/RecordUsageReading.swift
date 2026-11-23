import TendbarDomain

/// Files a status line reading under the account it belongs to. The profile's signed-in email alone is not enough:
/// after switching accounts, sessions started before the switch keep sending the old account's limits, and filing
/// them under the new email made the figures jump between the two accounts.
@MainActor
public final class RecordUsageReading {
    private let repository: UsageRepository
    private let output: UsageOutput
    private let emails: AccountEmailResolving
    private let checkWarnings: CheckLimitWarnings
    /// The account email each session's readings went to, for a reading the reset times cannot place.
    private var sessionEmails: [String: String] = [:]
    private static let rememberedSessions = 200

    public init(repository: UsageRepository, output: UsageOutput, emails: AccountEmailResolving, checkWarnings: CheckLimitWarnings) {
        self.repository = repository
        self.output = output
        self.emails = emails
        self.checkWarnings = checkWarnings
    }

    public func execute(_ reading: UsageReading) {
        var store = repository.load()
        let signedIn = emails.email(configDirectory: reading.configDirectory)
        let email = email(for: reading, in: store, signedIn: signedIn)
        guard store.record(reading, email: email, signedIn: email?.lowercased() == signedIn?.lowercased()) else { return }
        repository.save(store)
        output.show(store)
        checkWarnings.execute()
    }

    /// The account with the same reset times, else the one this session used before, else the one signed in now.
    private func email(for reading: UsageReading, in store: UsageStore, signedIn: String?) -> String? {
        let email = store.account(matching: reading)?.email
            ?? reading.sessionID.flatMap { sessionEmails[$0] }
            ?? signedIn
        if let session = reading.sessionID, let email {
            if sessionEmails.count >= Self.rememberedSessions, sessionEmails[session] == nil { sessionEmails.removeAll() }
            sessionEmails[session] = email
        }
        return email
    }
}
