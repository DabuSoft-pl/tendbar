import Foundation
import Observation
import TendbarKit

struct ReceivedEvent: Identifiable, Sendable {
    let id = UUID()
    let envelope: HookEnvelope
    let payload: HookPayload?
}

@MainActor
@Observable
final class AppModel {
    static let recentLimit = 50

    private(set) var events: [ReceivedEvent] = []
    private(set) var startError: String?
    private let server: UnixSocketServer

    init(socketPath: String = TendbarPaths.socketPath(environment: ProcessInfo.processInfo.environment)) {
        server = UnixSocketServer(path: socketPath)
        start()
    }

    var hookExecutablePath: String? {
        Bundle.main.url(forAuxiliaryExecutable: "tendbar-hook")?.path
    }

    private func start() {
        do {
            try server.start { [weak self] data in
                EventLog.append(data)
                guard let envelope = try? HookEnvelope.decoder.decode(HookEnvelope.self, from: data) else { return }
                let event = ReceivedEvent(envelope: envelope, payload: try? envelope.payload())
                Task { @MainActor in self?.receive(event) }
            }
        } catch {
            startError = String(describing: error)
        }
    }

    private func receive(_ event: ReceivedEvent) {
        events.insert(event, at: 0)
        if events.count > Self.recentLimit {
            events.removeLast(events.count - Self.recentLimit)
        }
    }
}
