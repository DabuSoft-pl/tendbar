import Foundation
import Testing
import TendbarApplication
import TendbarDomain

@MainActor
@Suite struct CheckLimitWarningsTests {
    let usage = InMemoryUsage()
    let fired = InMemoryFiredWarnings()
    let alerts = RecordingAlerts()
    let flasher = RecordingFlasher()
    let settings = StubSettings()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var check: CheckLimitWarnings {
        CheckLimitWarnings(usage: usage, fired: fired, alerts: alerts, flasher: flasher, settings: settings, clock: FixedClock(date: now))
    }

    private func account(five: Double) -> AccountUsage {
        AccountUsage(id: "|me@example.com", email: "me@example.com", fiveHour: LimitWindow(usedPercentage: five, resetsAt: now.addingTimeInterval(3600)), updatedAt: now)
    }

    @Test func warnsOnceAtEighty() {
        usage.store = UsageStore(accounts: [account(five: 83)])

        check.execute()
        check.execute()

        #expect(alerts.limits.map(\.threshold) == [80])
        #expect(flasher.tones.isEmpty)
    }

    @Test func flashesAtNinety() {
        usage.store = UsageStore(accounts: [account(five: 93)])

        check.execute()

        #expect(alerts.limits.map(\.threshold) == [90])
        #expect(flasher.tones == [.attention])
    }

    @Test func remembersTheWarningEvenWhenLimitBannersAreOff() {
        settings.alertSettings.notifyLimits = false
        usage.store = UsageStore(accounts: [account(five: 93)])

        check.execute()
        settings.alertSettings.notifyLimits = true
        check.execute()

        #expect(alerts.limits.isEmpty)
        #expect(!fired.keys.isEmpty)
    }
}
