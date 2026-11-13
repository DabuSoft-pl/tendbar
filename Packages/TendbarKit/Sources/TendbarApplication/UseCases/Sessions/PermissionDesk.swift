import TendbarDomain

/// Permission prompts waiting for an answer from a banner, one per session. A hook waits on each until it is
/// answered or released; the terminal prompt stays usable the whole time, and whichever answers first decides.
@MainActor
public final class PermissionDesk {
    private var pending: [String: (ask: PermissionAsk, reply: PermissionReply)] = [:]
    private let alerts: AlertPresenting

    public init(alerts: AlertPresenting) {
        self.alerts = alerts
    }

    func hold(_ ask: PermissionAsk, reply: PermissionReply) {
        pending[ask.sessionID]?.reply.send(nil)
        pending[ask.sessionID] = (ask, reply)
    }

    /// Lets the hook go without a decision, once the session has moved on.
    func release(sessionID: String) {
        pending.removeValue(forKey: sessionID)?.reply.send(nil)
    }

    public func isWaiting(sessionID: String) -> Bool {
        pending[sessionID] != nil
    }

    /// Answers the prompt a banner showed. Returns false when that prompt is gone or another one replaced it.
    @discardableResult
    public func answer(askID: String, sessionID: String, decision: PermissionDecision) -> Bool {
        guard let entry = pending[sessionID], entry.ask.id == askID else { return false }
        pending.removeValue(forKey: sessionID)
        entry.reply.send(decision)
        alerts.dismiss(sessionID: sessionID)
        return true
    }
}
