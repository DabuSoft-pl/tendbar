import Foundation
import TendbarDomain

/// Runs on a timer: reminds about waits that went unanswered and flags working sessions that went quiet.
@MainActor
public final class CheckAttention {
    private let repository: SessionRepository
    private let output: SessionsOutput
    private let alerts: AlertPresenting
    private let flasher: ScreenFlashing
    private let settings: AlertSettingsProviding
    private let clock: Clock

    public init(
        repository: SessionRepository,
        output: SessionsOutput,
        alerts: AlertPresenting,
        flasher: ScreenFlashing,
        settings: AlertSettingsProviding,
        clock: Clock
    ) {
        self.repository = repository
        self.output = output
        self.alerts = alerts
        self.flasher = flasher
        self.settings = settings
        self.clock = clock
    }

    public func execute() {
        let now = clock.now()
        let settings = settings.alertSettings
        var store = repository.load()
        var due: [(AlertKind, Session)] = []

        if let after = settings.remindAfter {
            for session in Attention.dueReminders(in: store, now: now, after: after) {
                store.markReminded(session.id)
                due.append((.reminder, session))
            }
        }
        if let after = settings.quietAfter {
            for session in Attention.newlyQuiet(in: store, now: now, after: after) {
                store.markQuiet(session.id)
                due.append((.quiet, session))
            }
        }
        guard !due.isEmpty else { return }
        repository.save(store)
        output.show(store)

        var flashed = false
        for (kind, session) in due where settings.notifies(kind) && !settings.mutes(session) {
            alerts.present(kind, for: session, sound: settings.alertSound)
            if !flashed, settings.flashes(kind) {
                flasher.flash(FlashTone(kind))
                flashed = true
            }
        }
    }
}
