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
        var activity: ActivityRepository
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
        var processes: SessionProcessChecking
        var clock: Clock
    }

    let preferences: Preferences
    let updates: SoftwareUpdate
    let statusMenu = StatusItemMenu()
    let sessions = SessionsViewModel()
    let usage = UsageViewModel()
    let activity = ActivityViewModel()
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
    private let checkAttention: CheckAttention
    private let endGoneSessions: EndGoneSessions
    private let checkWarnings: CheckLimitWarnings
    let permissionDesk: PermissionDesk
    private var timer: Timer?
    private var listener: HookEventListener?
    private var notch: NotchController?
    private var shortcut: GlobalShortcut?

    init(preferences: Preferences, adapters a: Adapters, eventLog: URL, dataFolder: URL, updates: SoftwareUpdate = SoftwareUpdate(starting: false)) {
        self.preferences = preferences
        self.updates = updates
        system = SystemViewModel(eventLog: eventLog, dataFolder: dataFolder)

        checkWarnings = CheckLimitWarnings(
            usage: a.usage, fired: a.firedWarnings, alerts: a.alerts, flasher: a.flasher, settings: preferences, clock: a.clock
        )
        permissionDesk = PermissionDesk(alerts: a.alerts)
        startSessions = StartSessions(repository: a.sessions, output: sessions, clock: a.clock)
        startUsage = StartUsage(repository: a.usage, output: usage, checkWarnings: checkWarnings)
        handleHookEvent = HandleHookEvent(
            repository: a.sessions, output: sessions, alerts: a.alerts, flasher: a.flasher, settings: preferences, transcripts: a.transcripts,
            activity: a.activity, activityOutput: activity, desk: permissionDesk
        )
        checkAttention = CheckAttention(
            repository: a.sessions, output: sessions, alerts: a.alerts, flasher: a.flasher, settings: preferences, clock: a.clock
        )
        endGoneSessions = EndGoneSessions(
            repository: a.sessions, output: sessions, processes: a.processes, desk: permissionDesk, clock: a.clock
        )
        recordUsage = RecordUsageReading(repository: a.usage, output: usage, emails: a.emails, checkWarnings: checkWarnings)

        sessionActions = SessionsController(
            model: sessions,
            repository: a.sessions,
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
        activity.show(a.activity.load())
        claudeCodeActions.refreshConnection()
    }

    /// Reminders, quiet sessions, closed tabs and limit resets have no event of their own, so a timer looks for them.
    private func startTimer() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.endGoneSessions.execute()
                self?.checkAttention.execute()
                self?.checkWarnings.checkResets()
                self?.usage.tick()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        endGoneSessions.execute()
        checkAttention.execute()
        checkWarnings.checkResets()
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
                activity: JSONActivityRepository(),
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
                processes: SessionProcessChecker(),
                clock: SystemClock()
            ),
            eventLog: TendbarPaths.eventLog,
            dataFolder: TendbarPaths.supportDirectory,
            updates: SoftwareUpdate(starting: true)
        )
        notifications.onOpen = { [weak container] id in container?.sessionActions.open(sessionID: id) }
        notifications.onAnswer = { [weak container] askID, sessionID, decision in
            container?.permissionDesk.answer(askID: askID, sessionID: sessionID, decision: decision)
        }
        container.listen(on: TendbarPaths.socketPath(environment: ProcessInfo.processInfo.environment))
        container.systemActions.requestNotifications()
        container.showNotch()
        container.listenForShortcut()
        container.statusMenu.updates = container.updates
        container.statusMenu.start()
        container.startTimer()
        DispatchQueue.main.async { preferences.theme.apply() }
        return container
    }

    private func listen(on socketPath: String) {
        let filter = EventLogFilter { UserDefaults.standard.bool(forKey: EventLog.enabledKey) }
        let listener = HookEventListener(socketPath: socketPath, logFilter: filter)
        do {
            try listener.start { [weak self] message, permission in
                guard let self else {
                    permission?.reply.send(nil)
                    return
                }
                receive(message, permission: permission)
            }
            self.listener = listener
        } catch {
            sessions.listenerError = String(describing: error)
        }
    }

    private func receive(_ message: InboundMessage, permission: (ask: PermissionAsk, reply: PermissionReply)?) {
        switch message {
        case let .hook(event):
            Task { await handleHookEvent.execute(event, permission: permission) }
        case let .usage(reading):
            recordUsage.execute(reading)
        }
    }

    private func listenForShortcut() {
        let shortcut = GlobalShortcut { [weak self] in
            guard let self else { return }
            // The panel is closed, so a sound is the only way to say nothing waits or the jump failed.
            if !sessionActions.openNextSession() || sessions.jumpMessage != nil { NSSound.beep() }
        }
        system.shortcutTaken = !shortcut.register(preferences.nextSessionShortcut)
        preferences.onShortcutChange = { [weak self, weak shortcut] in
            self?.system.shortcutTaken = shortcut?.register($0) == false
        }
        self.shortcut = shortcut
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
