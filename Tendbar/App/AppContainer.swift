import AppKit
import Foundation
import TendbarApplication
import TendbarDomain
import TendbarInfrastructure

/// Composition root: the one place that knows every layer. Read it in three parts: `Adapters` lists what the app
/// needs from the outside world, `init` hands them to each feature's assembly (`App/Assembly`), and `live()` picks
/// the real adapters and starts the socket, the notch, the shortcut and the timer.
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

    let permissionDesk: PermissionDesk
    /// The features the timer and the hook socket keep running after start.
    private let sessionsFeature: SessionsAssembly
    private let usageFeature: UsageAssembly
    private var timer: Timer?
    private var listener: HookEventListener?
    private var notch: NotchController?
    private var shortcut: GlobalShortcut?

    init(preferences: Preferences, adapters a: Adapters, eventLog: URL, dataFolder: URL, updates: SoftwareUpdate = SoftwareUpdate(starting: false)) {
        self.preferences = preferences
        self.updates = updates
        system = SystemViewModel(eventLog: eventLog, dataFolder: dataFolder)

        // Each feature builds its own use cases and controller.
        sessionsFeature = SessionsAssembly(a, model: sessions, activity: activity, preferences: preferences)
        usageFeature = UsageAssembly(a, model: usage, preferences: preferences)
        sessionActions = sessionsFeature.controller
        permissionDesk = sessionsFeature.desk
        usageActions = usageFeature.controller
        claudeCodeActions = ClaudeCodeAssembly(a, model: claudeCode).controller
        systemActions = SystemAssembly(a, model: system, preferences: preferences).controller

        sessionsFeature.start.execute()
        usageFeature.start.execute()
        activity.show(a.activity.load())
        claudeCodeActions.refreshConnections()
    }

    /// Reminders, quiet sessions, closed tabs and limit resets have no event of their own, so a timer looks for them.
    private func startTimer() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sessionsFeature.endGone.execute()
                self?.sessionsFeature.checkAttention.execute()
                self?.sessionsFeature.handleHookEvent.finishPendingStops()
                self?.usageFeature.checkWarnings.checkResets()
                self?.usage.tick()
                self?.claudeCodeActions.refreshConnections()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sessionsFeature.endGone.execute()
        sessionsFeature.checkAttention.execute()
        usageFeature.checkWarnings.checkResets()
    }

    /// The real app: JSON files, the hook socket, Notification Center, AppleScript and the notch.
    static func live() -> AppContainer {
        let notifications = UserNotificationsAlerts()
        let hookPath = Bundle.main.url(forAuxiliaryExecutable: "tendbar-hook")?.path
        let preferences = Preferences()
        notifications.birdVolume = { [preferences] in Float(preferences.soundVolume) }
        let container = AppContainer(
            preferences: preferences,
            adapters: Adapters(
                sessions: JSONSessionRepository(),
                usage: JSONUsageRepository(),
                activity: JSONActivityRepository(),
                firedWarnings: UserDefaultsFiredWarningRepository(),
                profiles: UserDefaultsProfileRepository(),
                alerts: ShortcutTrigger(alerts: notifications, preferences: preferences),
                permissions: notifications,
                flasher: EdgeGlow { [preferences] in preferences.hideFromCapture },
                navigator: AppleScriptTerminalNavigator(),
                emails: AccountEmailCache(),
                transcripts: FileTranscriptReader(),
                connector: hookPath.map(ClaudeHookConnector.init(hookPath:)),
                profileDirectories: ClaudeProfileDirectories(),
                loginItems: ServiceManagementLoginItems(),
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
        container.statusMenu.claudeCode = container.claudeCode
        container.statusMenu.connectHooks = { [weak container] in container?.claudeCodeActions.connectAll() }
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
            Task { await sessionsFeature.handleHookEvent.execute(event, permission: permission) }
            if event.kind == .stop { Task { await sessionsFeature.handleHookEvent.waitOutStop() } }
        case let .usage(reading):
            usageFeature.record.execute(reading)
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

    #if DEBUG
    func showDemoNotch() { showNotch() }
    #endif

    private func showNotch() {
        let notch = NotchController(
            sessions: sessions, sessionActions: sessionActions, usage: usage, claudeCode: claudeCode, preferences: preferences
        )
        preferences.onNotchViewChange = { [weak notch] in notch?.update() }
        preferences.onLogEventsChange = { enabled in if !enabled { EventLog.remove() } }
        self.notch = notch
    }
}
