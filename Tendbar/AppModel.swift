import Foundation
import Observation
import ServiceManagement
import TendbarKit
import UserNotifications

@MainActor
@Observable
final class AppModel {
    private(set) var store: SessionStore
    private(set) var usage = UsagePersistence.load()
    @ObservationIgnored private let emailCache = AccountEmailCache()
    private(set) var connection: HookInstaller.Status?
    private(set) var connectionError: String?
    private(set) var startError: String?
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var notificationError: String?
    private(set) var jumpMessage: String?
    private(set) var launchAtLogin: SMAppService.Status = LaunchAtLogin.status
    private(set) var launchAtLoginError: String?
    let preferences = Preferences()
    @ObservationIgnored private let server: UnixSocketServer
    @ObservationIgnored private let installer: HookInstaller?
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private let glow = EdgeGlow()
    @ObservationIgnored private var notch: NotchController?

    static var hookExecutablePath: String? {
        Bundle.main.url(forAuxiliaryExecutable: "tendbar-hook")?.path
    }

    init(socketPath: String = TendbarPaths.socketPath(environment: ProcessInfo.processInfo.environment)) {
        var store = SessionPersistence.load()
        store.prune(now: Date())
        self.store = store
        server = UnixSocketServer(path: socketPath)
        installer = Self.hookExecutablePath.map { HookInstaller(settingsURL: HookInstaller.settingsURL(), hookPath: $0) }
        notifier.onOpen = { [weak self] id in self?.open(sessionID: id) }
        start()
        refreshConnection()
        requestNotifications()
        notch = NotchController(model: self)
        watchClaudeSwap()
        checkLimits()
    }

    func refreshNotch() {
        notch?.update()
    }

    var sessions: [Session] {
        store.ordered
    }

    var needsYouCount: Int {
        store.needsYouCount
    }

    func refresh() {
        refreshConnection()
        refreshProfiles()
        launchAtLogin = LaunchAtLogin.status
        Task { notificationStatus = await notifier.authorizationStatus() }
    }

    struct Profile: Identifiable {
        let directory: String?
        let email: String?
        let connection: HookInstaller.Status?

        var id: String { directory ?? "" }
        var launchCommand: String {
            directory.map { ClaudeProfiles.launchCommand(for: URL(fileURLWithPath: $0)) } ?? "claude"
        }
    }

    private(set) var profiles: [Profile] = []
    private(set) var profileError: String?
    private static let profilesKey = "profiles"

    private var extraProfileDirectories: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.profilesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.profilesKey) }
    }

    func refreshProfiles() {
        let directories: [String?] = [nil] + extraProfileDirectories.map(Optional.some)
        profiles = directories.map { directory in
            Profile(
                directory: directory,
                email: ClaudeAccount.email(configDirectory: directory),
                connection: Self.hookExecutablePath.flatMap {
                    try? HookInstaller(settingsURL: HookInstaller.settingsURL(configDirectory: directory), hookPath: $0).status()
                }
            )
        }
    }

    func addProfile(named name: String) {
        do {
            let directory = try ClaudeProfiles.create(named: name).path
            if !extraProfileDirectories.contains(directory) { extraProfileDirectories.append(directory) }
            profileError = nil
        } catch ClaudeProfileError.invalidName {
            profileError = String(localized: "Nazwa może mieć 1–32 znaki: małe litery, cyfry i myślniki.")
        } catch {
            profileError = error.localizedDescription
        }
        refreshProfiles()
    }

    func removeProfile(_ profile: Profile) {
        guard let directory = profile.directory else { return }
        extraProfileDirectories.removeAll { $0 == directory }
        refreshProfiles()
    }

    func connect(_ profile: Profile) {
        guard let path = Self.hookExecutablePath else { return }
        do {
            try HookInstaller(settingsURL: HookInstaller.settingsURL(configDirectory: profile.directory), hookPath: path).connect()
            profileError = nil
        } catch {
            profileError = String(describing: error)
        }
        refreshConnection()
        refreshProfiles()
    }

    func refreshConnection() {
        guard let installer else {
            connection = nil
            return
        }
        do {
            connection = try installer.status()
            connectionError = nil
        } catch {
            connectionError = String(describing: error)
        }
    }

    func connect() {
        change { try $0.connect() }
    }

    func disconnect() {
        change { try $0.disconnect() }
    }

    func requestNotifications() {
        Task {
            notificationStatus = await notifier.requestAuthorization()
            notificationError = notifier.lastError
        }
    }

    func sendTestNotification() {
        Task {
            notificationStatus = await notifier.requestAuthorization()
            notificationError = notifier.lastError
            do {
                try await notifier.postTest(sound: preferences.playSound)
            } catch {
                notificationError = error.localizedDescription
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = LaunchAtLogin.status
    }

    func markSeen(_ session: Session) {
        store.markSeen(session.id)
        notifier.clear(session.id)
        persist()
    }

    func markAllSeen() {
        for session in store.sessions.values where session.unread { notifier.clear(session.id) }
        store.markAllSeen()
        persist()
    }

    func removeEnded() {
        store.removeEnded()
        persist()
    }

    func select(_ session: Session) {
        markSeen(session)
        switch TerminalJumper.jump(to: session.terminal) {
        case .jumped, .activated:
            jumpMessage = nil
        case .notRunning:
            jumpMessage = String(localized: "Terminal tej sesji nie jest uruchomiony.")
        case .unavailable:
            jumpMessage = String(localized: "Nie umiem jeszcze przełączyć na ten terminal.")
        case let .notAuthorized(app):
            jumpMessage = String(localized: "Zezwól Tendbarowi na sterowanie aplikacją \(app): Ustawienia systemowe → Prywatność i ochrona → Automatyzacja.")
        case let .failed(message):
            jumpMessage = String(localized: "Nie udało się przełączyć na sesję: \(message)")
        }
    }

    func dismissJumpMessage() {
        jumpMessage = nil
    }

    private func open(sessionID: String) {
        guard let session = store.sessions[sessionID] else { return }
        select(session)
    }

    private func change(_ action: (HookInstaller) throws -> URL?) {
        guard let installer else { return }
        do {
            _ = try action(installer)
            connectionError = nil
        } catch {
            connectionError = String(describing: error)
        }
        refreshConnection()
    }

    private func start() {
        do {
            try server.start { [weak self] data in
                EventLog.append(data)
                guard let envelope = try? HookEnvelope.decoder.decode(HookEnvelope.self, from: data) else { return }
                if envelope.isStatusLine {
                    Task { @MainActor in self?.receiveStatusLine(envelope) }
                    return
                }
                guard let payload = try? envelope.payload() else { return }
                Task { @MainActor in self?.receive(payload, envelope: envelope) }
            }
        } catch {
            startError = String(describing: error)
        }
    }

    private func receiveStatusLine(_ envelope: HookEnvelope) {
        let email = emailCache.email(configDirectory: envelope.terminal.configDirectory)
        guard usage.apply(envelope, email: email) else { return }
        try? UsagePersistence.save(usage)
        checkLimits()
    }

    private func watchClaudeSwap() {
        Task { [weak self] in
            var lastModified: Date?
            while !Task.isCancelled {
                let url = ClaudeSwapUsage.defaultURL
                let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
                if let modified, modified != lastModified {
                    lastModified = modified
                    let readings = await Task.detached(priority: .utility) { ClaudeSwapUsage.read(from: url) }.value
                    guard let self else { return }
                    var changed = false
                    for reading in readings where self.usage.merge(reading) { changed = true }
                    if changed {
                        try? UsagePersistence.save(self.usage)
                        self.checkLimits()
                    }
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private static let firedLimitsKey = "limits.fired"

    private func checkLimits() {
        let now = Date()
        var fired = Set(UserDefaults.standard.stringArray(forKey: Self.firedLimitsKey) ?? [])
        var warnings: [(AccountUsage, LimitWarning)] = []
        for account in usage.ordered {
            for warning in LimitWarnings.pending(for: account, now: now, fired: fired) {
                warnings.append((account, warning))
                fired.formUnion(LimitWarnings.keys(firing: warning))
            }
        }
        guard !warnings.isEmpty else { return }
        UserDefaults.standard.set(Array(fired.sorted().suffix(200)), forKey: Self.firedLimitsKey)
        guard preferences.notifyLimits else { return }
        for (account, warning) in warnings {
            let reset = warning.resetsAt.formatted(.relative(presentation: .named))
            notifier.postLimit(
                title: String(localized: "Limit \(Self.windowName(warning.window)): \(Int(warning.percentage.rounded())) %"),
                body: String(localized: "\(accountName(account)), reset \(reset)"),
                identifier: LimitWarnings.key(accountID: warning.accountID, window: warning.window, resetsAt: warning.resetsAt, threshold: warning.threshold),
                sound: preferences.playSound
            )
        }
        if preferences.edgeGlow, warnings.contains(where: { $0.1.threshold >= 90 }) { glow.flash(.orange) }
    }

    static func windowName(_ window: String) -> String {
        switch window {
        case LimitWarnings.fiveHour: String(localized: "5 godz.")
        case LimitWarnings.sevenDay: String(localized: "tygodniowy")
        default: window
        }
    }

    func accountName(_ account: AccountUsage) -> String {
        account.email
            ?? account.configDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? String(localized: "Konto domyślne")
    }

    func forget(_ account: AccountUsage) {
        usage.remove(account.id)
        try? UsagePersistence.save(usage)
    }

    private func receive(_ payload: HookPayload, envelope: HookEnvelope) {
        let previous = store.sessions[payload.sessionID]?.state
        let session = store.apply(payload, envelope: envelope)
        persist()
        if session.state == .working || session.state == .ended {
            notifier.clear(session.id)
        }
        let alert = AlertPolicy.alert(from: previous, to: session.state)

        guard payload.event == "Stop", let path = session.transcriptPath else {
            if let alert { notify(alert, sessionID: session.id) }
            return
        }
        Task {
            let text = await Task.detached(priority: .utility) {
                TranscriptReader.lastAssistantText(at: URL(fileURLWithPath: path)).map { TranscriptReader.preview(of: $0) }
            }.value
            if let text {
                store.setPreview(text, for: session.id)
                persist()
            }
            if let alert { notify(alert, sessionID: session.id) }
        }
    }

    private func notify(_ kind: AlertKind, sessionID: String) {
        guard preferences.isEnabled(kind), let session = store.sessions[sessionID] else { return }
        let body: String
        switch kind {
        case .needsYou, .failed: body = session.message ?? session.state.hint
        case .done: body = session.preview ?? session.state.hint
        }
        notifier.post(kind, for: session, body: body, sound: preferences.playSound)
        if preferences.edgeGlow, kind != .done { glow.flash(kind.color) }
    }

    func previewGlow() {
        glow.flash(AlertKind.needsYou.color)
    }

    private func persist() {
        try? SessionPersistence.save(store)
    }
}
