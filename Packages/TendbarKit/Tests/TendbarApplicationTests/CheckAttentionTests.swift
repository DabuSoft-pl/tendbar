import Foundation
import Testing
import TendbarApplication
import TendbarDomain

@MainActor
@Suite struct CheckAttentionTests {
    let sessions = InMemorySessions()
    let alerts = RecordingAlerts()
    let flasher = RecordingFlasher()
    let settings = StubSettings()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func useCase(minutesLater minutes: Double) -> CheckAttention {
        CheckAttention(
            repository: sessions,
            output: sessions,
            alerts: alerts,
            flasher: flasher,
            settings: settings,
            clock: FixedClock(date: start.addingTimeInterval(minutes * 60))
        )
    }

    private func apply(_ name: String, at minutes: Double = 0, cwd: String = "/Users/me/app") {
        sessions.store.apply(HookEvent(sessionID: "s1", kind: HookEvent.Kind(name: name), cwd: cwd, sentAt: start.addingTimeInterval(minutes * 60)))
    }

    @Test func remindsAboutALongWaitOnce() {
        apply("UserPromptSubmit")
        apply("PermissionRequest", at: 1)

        useCase(minutesLater: 3).execute()
        #expect(alerts.presented.isEmpty)

        useCase(minutesLater: 7).execute()
        useCase(minutesLater: 9).execute()
        #expect(alerts.presented.map(\.0) == [.reminder])
        #expect(flasher.tones == [.attention])
        #expect(sessions.store.sessions["s1"]?.remindedWait == true)
    }

    @Test func noReminderWhenTurnedOffOrMuted() {
        apply("UserPromptSubmit")
        apply("PermissionRequest", at: 1)
        settings.alertSettings.mutedFolders = ["/Users/me/app"]

        useCase(minutesLater: 10).execute()
        #expect(alerts.presented.isEmpty)
        #expect(sessions.store.sessions["s1"]?.remindedWait == true)
    }

    @Test func flagsAQuietWorkingSession() {
        apply("UserPromptSubmit")

        useCase(minutesLater: 16).execute()
        useCase(minutesLater: 20).execute()

        #expect(alerts.presented.map(\.0) == [.quiet])
        #expect(sessions.store.sessions["s1"]?.flaggedQuiet == true)
    }

    @Test func quietCheckCanBeTurnedOff() {
        settings.alertSettings.quietAfter = nil
        apply("UserPromptSubmit")

        useCase(minutesLater: 60).execute()

        #expect(alerts.presented.isEmpty)
    }
}

@MainActor
@Suite struct LimitResetAnnouncementTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func announcesAWarnedWindowOnceItResets() {
        let resetsAt = now.addingTimeInterval(-60)
        let usage = InMemoryUsage([AccountUsage(id: "a", fiveHour: LimitWindow(usedPercentage: 92, resetsAt: resetsAt), updatedAt: now.addingTimeInterval(-3600))])
        let fired = InMemoryFiredWarnings()
        fired.keys = [LimitWarnings.key(accountID: "a", window: LimitWarnings.fiveHour, resetsAt: resetsAt, threshold: 80)]
        let alerts = RecordingAlerts()
        let check = CheckLimitWarnings(usage: usage, fired: fired, alerts: alerts, flasher: RecordingFlasher(), settings: StubSettings(), clock: FixedClock(date: now))

        check.checkResets()
        check.checkResets()

        #expect(alerts.resets.count == 1)
    }
}
