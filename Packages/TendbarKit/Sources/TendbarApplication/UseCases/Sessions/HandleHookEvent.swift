import Foundation
import TendbarDomain

/// Applies one hook event, reads the session's title and, when a turn ends, the reply preview and tells the user when a session needs them.
@MainActor
public final class HandleHookEvent {
    private let repository: SessionRepository
    private let output: SessionsOutput
    private let alerts: AlertPresenting
    private let flasher: ScreenFlashing
    private let settings: AlertSettingsProviding
    private let transcripts: TranscriptReading
    private let activity: ActivityRepository
    private let activityOutput: ActivityOutput
    private let calendar: Calendar
    private let desk: PermissionDesk?

    public init(
        repository: SessionRepository,
        output: SessionsOutput,
        alerts: AlertPresenting,
        flasher: ScreenFlashing,
        settings: AlertSettingsProviding,
        transcripts: TranscriptReading,
        activity: ActivityRepository,
        activityOutput: ActivityOutput,
        calendar: Calendar = .current,
        desk: PermissionDesk? = nil
    ) {
        self.desk = desk
        self.repository = repository
        self.output = output
        self.alerts = alerts
        self.flasher = flasher
        self.settings = settings
        self.transcripts = transcripts
        self.activity = activity
        self.activityOutput = activityOutput
        self.calendar = calendar
    }

    /// `permission` comes with a PermissionRequest whose hook waits for an answer. It always gets one: a decision
    /// from the banner later, or nil right away when the banner will not ask.
    public func execute(_ event: HookEvent, permission: (ask: PermissionAsk, reply: PermissionReply)? = nil) async {
        var held = false
        defer { if let permission, !held { permission.reply.send(nil) } }
        var store = repository.load()
        let before = store.sessions[event.sessionID]
        let previous = before?.state
        let session = store.apply(event)
        if session.state != .needsYou { desk?.release(sessionID: session.id) }
        commit(store)
        record(previous: before, current: session, at: event.sentAt)

        if session.state == .working || session.state == .ended {
            alerts.dismiss(sessionID: session.id)
        }
        let alert = AlertPolicy.alert(from: previous, to: session.state)

        if let path = session.transcriptPath, Self.readsTranscript(after: event.kind) {
            let title = await transcripts.title(at: path)
            let preview = event.kind == .stop ? await transcripts.lastReplyPreview(at: path) : nil
            if (title != nil && title != session.title) || preview != nil {
                var latest = repository.load()
                if let title { latest.setTitle(title, for: session.id) }
                if let preview { latest.setPreview(preview, for: session.id) }
                commit(latest)
            }
        }
        if let alert { held = notify(alert, sessionID: session.id, permission: permission) }
    }

    /// The title is looked up where a turn starts or ends and before a banner, not after every tool call.
    private static func readsTranscript(after kind: HookEvent.Kind) -> Bool {
        switch kind {
        case .sessionStart, .userPromptSubmit, .permissionRequest, .notification, .stop, .stopFailure: true
        case .postToolUse, .sessionEnd, .other: false
        }
    }

    /// Returns whether a permission prompt went to the banner and now waits there.
    private func notify(_ kind: AlertKind, sessionID: String, permission: (ask: PermissionAsk, reply: PermissionReply)?) -> Bool {
        let settings = settings.alertSettings
        guard settings.notifies(kind), var session = repository.load().sessions[sessionID], !settings.mutes(session) else { return false }
        if kind == .done, !settings.showsReplyPreview { session.preview = nil }
        var held = false
        if kind == .needsYou, settings.answersPermissions, let permission, let desk {
            desk.hold(permission.ask, reply: permission.reply)
            alerts.presentPermission(permission.ask, for: session, sound: settings.alertSound)
            held = true
        } else {
            alerts.present(kind, for: session, sound: settings.alertSound)
        }
        if settings.flashes(kind) { flasher.flash(FlashTone(kind)) }
        return held
    }

    private func record(previous: Session?, current: Session, at date: Date) {
        var stats = activity.load()
        guard stats.record(previous: previous, current: current, at: date, calendar: calendar) else { return }
        stats.prune(now: date, calendar: calendar)
        activity.save(stats)
        activityOutput.show(stats)
    }

    private func commit(_ store: SessionStore) {
        repository.save(store)
        output.show(store)
    }
}
