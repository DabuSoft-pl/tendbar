import TendbarDomain

/// Applies one hook event, reads the reply preview when a turn ends and tells the user when a session needs them.
@MainActor
public final class HandleHookEvent {
    private let repository: SessionRepository
    private let output: SessionsOutput
    private let alerts: AlertPresenting
    private let flasher: ScreenFlashing
    private let settings: AlertSettingsProviding
    private let transcripts: TranscriptReading

    public init(
        repository: SessionRepository,
        output: SessionsOutput,
        alerts: AlertPresenting,
        flasher: ScreenFlashing,
        settings: AlertSettingsProviding,
        transcripts: TranscriptReading
    ) {
        self.repository = repository
        self.output = output
        self.alerts = alerts
        self.flasher = flasher
        self.settings = settings
        self.transcripts = transcripts
    }

    public func execute(_ event: HookEvent) async {
        var store = repository.load()
        let previous = store.sessions[event.sessionID]?.state
        let session = store.apply(event)
        commit(store)

        if session.state == .working || session.state == .ended {
            alerts.dismiss(sessionID: session.id)
        }
        let alert = AlertPolicy.alert(from: previous, to: session.state)

        if event.kind == .stop, let path = session.transcriptPath,
           let preview = await transcripts.lastReplyPreview(at: path) {
            var latest = repository.load()
            latest.setPreview(preview, for: session.id)
            commit(latest)
        }
        if let alert { notify(alert, sessionID: session.id) }
    }

    private func notify(_ kind: AlertKind, sessionID: String) {
        let settings = settings.alertSettings
        guard settings.notifies(kind), var session = repository.load().sessions[sessionID], !settings.mutes(session) else { return }
        if kind == .done, !settings.showsReplyPreview { session.preview = nil }
        alerts.present(kind, for: session, sound: settings.sound)
        if settings.flashes(kind) { flasher.flash(FlashTone(kind)) }
    }

    private func commit(_ store: SessionStore) {
        repository.save(store)
        output.show(store)
    }
}
