import Foundation
import Observation
import TendbarKit

@MainActor
@Observable
final class AppModel {
    private(set) var store: SessionStore
    private(set) var connection: HookInstaller.Status?
    private(set) var connectionError: String?
    private(set) var startError: String?
    private let server: UnixSocketServer
    private let installer: HookInstaller?

    static var hookExecutablePath: String? {
        Bundle.main.url(forAuxiliaryExecutable: "tendbar-hook")?.path
    }

    init(socketPath: String = TendbarPaths.socketPath(environment: ProcessInfo.processInfo.environment)) {
        var store = SessionPersistence.load()
        store.prune(now: Date())
        self.store = store
        server = UnixSocketServer(path: socketPath)
        installer = Self.hookExecutablePath.map { HookInstaller(settingsURL: HookInstaller.settingsURL(), hookPath: $0) }
        start()
        refreshConnection()
    }

    var sessions: [Session] {
        store.ordered
    }

    var needsYouCount: Int {
        store.needsYouCount
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

    func markSeen(_ session: Session) {
        store.markSeen(session.id)
        persist()
    }

    func markAllSeen() {
        store.markAllSeen()
        persist()
    }

    func removeEnded() {
        store.removeEnded()
        persist()
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
        let session = store.apply(payload, envelope: envelope)
        persist()
        guard payload.event == "Stop", let path = session.transcriptPath else { return }
        Task {
            let text = await Task.detached(priority: .utility) {
                TranscriptReader.lastAssistantText(at: URL(fileURLWithPath: path)).map { TranscriptReader.preview(of: $0) }
            }.value
            guard let text else { return }
            store.setPreview(text, for: session.id)
            persist()
        }
    }

    private func persist() {
        try? SessionPersistence.save(store)
    }
}
