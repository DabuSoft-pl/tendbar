import Foundation
import Observation
import ServiceManagement
import TendbarKit
import UserNotifications

@MainActor
@Observable
final class AppModel {
    private(set) var store: SessionStore
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
    }

    var sessions: [Session] {
        store.ordered
    }

    var needsYouCount: Int {
        store.needsYouCount
    }

    func refresh() {
        refreshConnection()
        launchAtLogin = LaunchAtLogin.status
        Task { notificationStatus = await notifier.authorizationStatus() }
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
                guard let envelope = try? HookEnvelope.decoder.decode(HookEnvelope.self, from: data),
                      let payload = try? envelope.payload()
                else { return }
                Task { @MainActor in self?.receive(payload, envelope: envelope) }
            }
        } catch {
            startError = String(describing: error)
        }
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
