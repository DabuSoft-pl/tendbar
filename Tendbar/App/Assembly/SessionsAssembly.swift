import TendbarApplication

/// Builds the sessions feature: the use cases a hook event or the timer runs and the controller behind the panel,
/// the pill and the banners.
@MainActor
struct SessionsAssembly {
    let desk: PermissionDesk
    let start: StartSessions
    let handleHookEvent: HandleHookEvent
    let checkAttention: CheckAttention
    let endGone: EndGoneSessions
    let controller: SessionsController

    init(_ a: AppContainer.Adapters, model: SessionsViewModel, activity: ActivityViewModel, preferences: Preferences) {
        desk = PermissionDesk(alerts: a.alerts, output: model)
        start = StartSessions(repository: a.sessions, output: model, clock: a.clock)
        handleHookEvent = HandleHookEvent(
            repository: a.sessions, output: model, alerts: a.alerts, flasher: a.flasher, settings: preferences, transcripts: a.transcripts,
            activity: a.activity, activityOutput: activity, desk: desk, navigator: a.navigator
        )
        checkAttention = CheckAttention(
            repository: a.sessions, output: model, alerts: a.alerts, flasher: a.flasher, settings: preferences, clock: a.clock
        )
        endGone = EndGoneSessions(repository: a.sessions, output: model, processes: a.processes, desk: desk, clock: a.clock)
        controller = SessionsController(
            model: model,
            repository: a.sessions,
            openSession: OpenSession(repository: a.sessions, output: model, alerts: a.alerts, navigator: a.navigator),
            markAllSeen: MarkAllSessionsSeen(repository: a.sessions, output: model, alerts: a.alerts),
            removeEnded: RemoveEndedSessions(repository: a.sessions, output: model),
            desk: desk
        )
    }
}
