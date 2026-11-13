import AppKit
import Foundation
import TendbarApplication
import TendbarDomain
import TendbarInfrastructure

/// Composition root: the one place that knows every layer. It builds the adapters, hands them to the use cases
/// through their ports and wires the use cases to the view models and controllers.
@MainActor
final class AppContainer {
    /// Everything the use cases need from the outside world, as ports.
    struct Adapters {
        var sessions: SessionRepository
        var usage: UsageRepository
        var firedWarnings: FiredWarningRepository
        var profiles: ProfileRepository
        var alerts: AlertPresenting
        var permissions: NotificationPermissions
        var flasher: ScreenFlashing
        var navigator: TerminalNavigating
        var emails: AccountEmailResolving
        var transcripts: TranscriptReading
        var connector: HookConnecting?
        var profileDirectories: ProfileDirectories
        var loginItems: LoginItemControlling
        var clock: Clock
    }

    let preferences: Preferences
    let sessions = SessionsViewModel()
    let usage = UsageViewModel()
    let claudeCode = ClaudeCodeViewModel()
    let system: SystemViewModel
    let sessionActions: SessionsController
    let usageActions: UsageController
    let claudeCodeActions: ClaudeCodeController
    let systemActions: SystemController

    private let startSessions: StartSessions
    private let startUsage: StartUsage
    private let handleHookEvent: HandleHookEvent
    private let recordUsage: RecordUsageReading
    private var listener: HookEventListener?
    private var notch: NotchController?

    init(preferences: Preferences, adapters a: Adapters, eventLog: URL, dataFolder: URL) {
        self.preferences = preferences
        system = SystemViewModel(eventLog: eventLog, dataFolder: dataFolder)

        let checkWarnings = CheckLimitWarnings(
            usage: a.usage, fired: a.firedWarnings, alerts: a.alerts, flasher: a.flasher, settings: preferences, clock: a.clock
        )
        startSessions = StartSessions(repository: a.sessions, output: sessions, clock: a.clock)
        startUsage = StartUsage(repository: a.usage, output: usage, checkWarnings: checkWarnings)
        handleHookEvent = HandleHookEvent(
            repository: a.sessions, output: sessions, alerts: a.alerts, flasher: a.flasher, settings: preferences, transcripts: a.transcripts
        )
        recordUsage = RecordUsageReading(repository: a.usage, output: usage, emails: a.emails, checkWarnings: checkWarnings)

        sessionActions = SessionsController(
            model: sessions,
            openSession: OpenSession(repository: a.sessions, output: sessions, alerts: a.alerts, navigator: a.navigator),
            markAllSeen: MarkAllSessionsSeen(repository: a.sessions, output: sessions, alerts: a.alerts),
            removeEnded: RemoveEndedSessions(repository: a.sessions, output: sessions)
        )
        usageActions = UsageController(forgetAccount: ForgetAccount(repository: a.usage, output: usage))
        claudeCodeActions = ClaudeCodeController(
            model: claudeCode,
            checkConnection: CheckHookConnection(connector: a.connector),
            changeConnection: ChangeHookConnection(connector: a.connector),
            listProfiles: ListProfiles(repository: a.profiles, emails: a.emails, connector: a.connector),
            addProfile: AddProfile(repository: a.profiles, directories: a.profileDirectories),
            removeProfile: RemoveProfile(repository: a.profiles)
        )
        systemActions = SystemController(
            model: system,
            checkPermission: CheckNotificationPermission(permissions: a.permissions),
            requestPermission: RequestNotificationPermission(permissions: a.permissions),
            sendTest: SendTestNotification(permissions: a.permissions, settings: preferences),
            previewFlash: PreviewScreenFlash(flasher: a.flasher),
            checkLaunchAtLogin: CheckLaunchAtLogin(loginItems: a.loginItems),
            setLaunchAtLogin: SetLaunchAtLogin(loginItems: a.loginItems)
        )

        startSessions.execute()
        startUsage.execute()
        claudeCodeActions.refreshConnection()
    }

    /// The real app: JSON files, the hook socket, Notification Center, AppleScript and the notch.
    static func live() -> AppContainer {
        let notifications = UserNotificationsAdapter()
        let hookPath = Bundle.main.url(forAuxiliaryExecutable: "tendbar-hook")?.path
        let preferences = Preferences()
        let container = AppContainer(
            preferences: preferences,
            adapters: Adapters(
                sessions: JSONSessionRepository(),
                usage: JSONUsageRepository(),
                firedWarnings: UserDefaultsFiredWarningRepository(),
                profiles: UserDefaultsProfileRepository(),
                alerts: notifications,
                permissions: notifications,
                flasher: EdgeGlow { [preferences] in preferences.hideFromCapture },
                navigator: AppleScriptTerminalNavigator(),
                emails: AccountEmailCache(),
                transcripts: FileTranscriptReader(),
                connector: hookPath.map(ClaudeHookConnector.init(hookPath:)),
                profileDirectories: ClaudeProfileDirectories(),
                loginItems: LaunchAtLoginService(),
                clock: SystemClock()
            ),
            eventLog: TendbarPaths.eventLog,
            dataFolder: TendbarPaths.supportDirectory
        )
        notifications.onOpen = { [weak container] id in container?.sessionActions.open(sessionID: id) }
        container.listen(on: TendbarPaths.socketPath(environment: ProcessInfo.processInfo.environment))
        container.systemActions.requestNotifications()
        container.showNotch()
        DispatchQueue.main.async { preferences.theme.apply() }
        return container
    }

    private func listen(on socketPath: String) {
        let filter = EventLogFilter { UserDefaults.standard.bool(forKey: EventLog.enabledKey) }
        let listener = HookEventListener(socketPath: socketPath, logFilter: filter)
        do {
            try listener.start { [weak self] message in self?.receive(message) }
            self.listener = listener
        } catch {
            sessions.listenerError = String(describing: error)
        }
    }

    private func receive(_ message: InboundMessage) {
        switch message {
        case let .hook(event):
            Task { await handleHookEvent.execute(event) }
        case let .usage(reading):
            recordUsage.execute(reading)
        }
    }

    private func showNotch() {
        let notch = NotchController(
            sessions: sessions, sessionActions: sessionActions, usage: usage, preferences: preferences
        )
        preferences.onNotchViewChange = { [weak notch] in notch?.update() }
        preferences.onLogEventsChange = { enabled in if !enabled { EventLog.remove() } }
        self.notch = notch
    }
}
