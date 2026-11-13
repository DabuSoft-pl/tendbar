import Foundation
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

    public func start(onMessage: @escaping @MainActor @Sendable (InboundMessage) -> Void) throws {
        let logFilter = logFilter
        try server.start { data in
            guard var envelope = try? HookEnvelope.decoder.decode(HookEnvelope.self, from: data) else { return }
            envelope.raw = HookRedaction.redact(Data(envelope.raw.utf8), statusLine: envelope.isStatusLine)
            if logFilter.shouldLog(envelope), let redacted = try? HookEnvelope.encoder.encode(envelope) {
                EventLog.append(redacted)
            }
            guard let message = envelope.message() else { return }
            Task { @MainActor in onMessage(message) }
        }
    }

    public func stop() {
        server.stop()
    }
}
