import Foundation

/// Decides which redacted envelopes reach the event log. Status line readings are logged only when the limits change,
/// and a run of tool calls only once, so the log keeps state changes instead of repeats.
public final class EventLogFilter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastLimits: [String: String] = [:]
    private var lastEvent: [String: String] = [:]
    private let isEnabled: @Sendable () -> Bool

    public init(isEnabled: @escaping @Sendable () -> Bool = { true }) {
        self.isEnabled = isEnabled
    }

    public func shouldLog(_ envelope: HookEnvelope) -> Bool {
        let object = (try? JSONSerialization.jsonObject(with: Data(envelope.raw.utf8))) as? [String: Any] ?? [:]
        let session = object["session_id"] as? String ?? ""
        let decision: Bool = lock.withLock {
            if envelope.isStatusLine {
                let limits = (object["rate_limits"]).flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
                    .map { String(decoding: $0, as: UTF8.self) } ?? ""
                defer { lastLimits[session] = limits }
                return lastLimits[session] != limits
            }
            let event = object["hook_event_name"] as? String ?? ""
            defer { lastEvent[session] = event }
            return !(event == "PostToolUse" && lastEvent[session] == "PostToolUse")
        }
        return decision && isEnabled()
    }
}
