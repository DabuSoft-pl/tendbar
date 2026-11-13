import Foundation
import TendbarApplication
import TendbarDomain

/// Inbound adapter: receives envelopes from `tendbar-hook`, redacts and logs them, and hands domain messages
/// to the app on the main actor.
public final class HookEventListener: Sendable {
    private let server: UnixSocketServer
    private let logFilter: EventLogFilter

    public init(socketPath: String, logFilter: EventLogFilter = EventLogFilter()) {
        server = UnixSocketServer(path: socketPath)
        self.logFilter = logFilter
    }

    /// A PermissionRequest comes with its prompt and the way back to the waiting hook; everything else with nil.
    public func start(
        onMessage: @escaping @MainActor @Sendable (InboundMessage, (ask: PermissionAsk, reply: PermissionReply)?) -> Void
    ) throws {
        let logFilter = logFilter
        try server.start { data, reply in
            guard var envelope = try? HookEnvelope.decoder.decode(HookEnvelope.self, from: data) else {
                reply.send(nil)
                return
            }
            let permission = envelope.permission
            envelope.permission = nil
            envelope.raw = HookRedaction.redact(Data(envelope.raw.utf8), statusLine: envelope.isStatusLine)
            if logFilter.shouldLog(envelope), let redacted = try? HookEnvelope.encoder.encode(envelope) {
                EventLog.append(redacted)
            }
            guard let message = envelope.message() else {
                reply.send(nil)
                return
            }
            guard let permission, case let .hook(event) = message, event.kind == .permissionRequest else {
                reply.send(nil)
                Task { @MainActor in onMessage(message, nil) }
                return
            }
            let ask = permission.ask(sessionID: event.sessionID)
            let waiting = SocketPermissionReply(reply)
            Task { @MainActor in onMessage(message, (ask, waiting)) }
        }
    }

    public func stop() {
        server.stop()
    }
}

/// Answers a waiting `tendbar-hook` over its socket connection.
final class SocketPermissionReply: PermissionReply {
    private let reply: SocketReply

    init(_ reply: SocketReply) {
        self.reply = reply
    }

    func send(_ decision: PermissionDecision?) {
        reply.send(PermissionAnswer.encode(decision))
    }
}
