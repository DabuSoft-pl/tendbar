import TendbarApplication

/// Builds the usage feature: limit readings from the statusLine, the warnings at 80% and 90%, forgetting an account.
@MainActor
struct UsageAssembly {
    let checkWarnings: CheckLimitWarnings
    let start: StartUsage
    let record: RecordUsageReading
    let controller: UsageController

    init(_ a: AppContainer.Adapters, model: UsageViewModel, preferences: Preferences) {
        checkWarnings = CheckLimitWarnings(
            usage: a.usage, fired: a.firedWarnings, alerts: a.alerts, flasher: a.flasher, settings: preferences, clock: a.clock
        )
        start = StartUsage(repository: a.usage, output: model, checkWarnings: checkWarnings)
        record = RecordUsageReading(repository: a.usage, output: model, emails: a.emails, checkWarnings: checkWarnings)
        controller = UsageController(forgetAccount: ForgetAccount(repository: a.usage, output: model))
    }
}
