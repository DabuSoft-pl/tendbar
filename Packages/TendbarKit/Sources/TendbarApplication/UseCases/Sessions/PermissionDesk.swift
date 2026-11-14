import TendbarDomain

/// Permission prompts waiting for an answer from a banner, the panel or the pill, one per session. A hook waits on
/// each until it is answered or released; the terminal prompt stays usable the whole time, and whichever answers
/// first decides.
@MainActor
public final class PermissionDesk {
    private var pending: [String: (ask: PermissionAsk, reply: PermissionReply)] = [:]
    private let alerts: AlertPresenting
    private let output: PermissionsOutput?

    public init(alerts: AlertPresenting, output: PermissionsOutput? = nil) {
        self.alerts = alerts
        self.output = output
    }

    func hold(_ ask: PermissionAsk, reply: PermissionReply) {
        pending[ask.sessionID]?.reply.send(nil)
        pending[ask.sessionID] = (ask, reply)
        publish()
    }

    /// Lets the hook go without a decision, once the session has moved on.
    func release(sessionID: String) {
        guard let entry = pending.removeValue(forKey: sessionID) else { return }
        entry.reply.send(nil)
        publish()
    }

    public func isWaiting(sessionID: String) -> Bool {
        pending[sessionID] != nil
    }

    /// Answers the prompt a banner, the panel or the pill showed. Returns false when that prompt is gone or another
    /// one replaced it.
    @discardableResult
    public func answer(askID: String, sessionID: String, decision: PermissionDecision) -> Bool {
        guard let entry = pending[sessionID], entry.ask.id == askID else { return false }
        pending.removeValue(forKey: sessionID)
        entry.reply.send(decision)
        alerts.dismiss(sessionID: sessionID)
        publish()
        return true
    }

    private func publish() {
        output?.show(Array(pending.values.map(\.ask)))
    }
}
