import Foundation

/// All known sessions and the rules for how hook events move them between states.
public struct SessionStore: Sendable, Equatable {
    public static let endedRetention: TimeInterval = 24 * 60 * 60
    public static let inactiveRetention: TimeInterval = 7 * 24 * 60 * 60
    public static let limit = 100
    public static let stopGrace: TimeInterval = 3 // seconds; Stop and SubagentStart race
    public static let backgroundGrace: TimeInterval = 20 // seconds; PA3 resumes its agent up to ~15 s after the main Stop

    public private(set) var sessions: [String: Session]

    public init(sessions: [Session] = []) {
        self.sessions = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }

    public var ordered: [Session] {
        sessions.values.sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
    }

    public var needsYouCount: Int {
        count(of: .needsYou)
    }

    public var hasUnread: Bool {
        sessions.values.contains { $0.unread }
    }

    /// Where the shortcut goes next: the session that has waited for you longest, then a failed turn you have not
    /// seen, then a finished reply you have not read, the oldest first within each.
    public var nextForYou: Session? {
        func rank(_ session: Session) -> Int? {
            switch session.state {
            case .needsYou: 0
            case .failed where session.unread: 1
            case .done where session.unread: 2
            default: nil
            }
        }
        return sessions.values
            .compactMap { session in rank(session).map { (session, $0) } }
            .min { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                let first = a.0.waitingSince ?? a.0.updatedAt
                let second = b.0.waitingSince ?? b.0.updatedAt
                return first == second ? a.0.id < b.0.id : first < second
            }?
            .0
    }

    public func count(of state: SessionState) -> Int {
        sessions.values.filter { $0.state == state }.count
    }

    @discardableResult
    public mutating func apply(_ event: HookEvent) -> Session {
        var session = sessions[event.sessionID] ?? Session(
            id: event.sessionID,
            terminal: event.terminal,
            startedAt: event.sentAt,
            updatedAt: event.sentAt
        )
        session.cwd = event.cwd ?? session.cwd
        session.transcriptPath = event.transcriptPath ?? session.transcriptPath
        session.terminal = event.terminal
        session.updatedAt = max(session.updatedAt, event.sentAt)
        session.flaggedQuiet = false
        let wasWaiting = session.state == .needsYou

        switch event.kind {
        case .sessionStart:
            if session.state == .ended { session.state = .idle }
        case .userPromptSubmit:
            session.state = .working
            session.turnStartedAt = event.sentAt
            session.turnWaited = 0
            session.stopDeferred = false
            session.stoppedAt = nil
            session.unread = false
            session.message = nil
        case .postToolUse:
            if session.state == .needsYou, event.agentID == session.waitingAgent {
                session.state = .working
                session.unread = false
                session.message = nil
            }
        case .permissionRequest:
            session.state = .needsYou
            session.waitingAgent = event.agentID
            session.unread = true
        case .notification:
            guard event.asksForAttention else { break }
            if session.state != .done { session.state = .needsYou }
            session.unread = true
            session.message = event.message ?? session.message
        case .stop:
            // Background subagents outlive the main turn; foreground ones have stopped by now. A SubagentStart may
            // still be on its way, so done waits out the grace (`finishPendingStops`) or the last SubagentStop.
            session.stopDeferred = true
            session.stoppedAt = session.runningAgents.isEmpty ? event.sentAt : nil
        case .subagentStart:
            // Foreground subagents start inside the working turn; one starting after the Stop is a background one.
            if session.stopDeferred || session.state == .done { session.usesBackgroundAgents = true }
            if let agent = event.agentID { session.runningAgents.insert(agent) }
        case .subagentStop:
            if let agent = event.agentID { session.runningAgents.remove(agent) }
            if session.stopDeferred, session.runningAgents.isEmpty,
               session.state == .working || session.state == .needsYou {
                session.stopDeferred = false
                session.stoppedAt = nil
                session.state = .done
                session.unread = true
                session.message = nil
            }
        case .stopFailure:
            session.stopDeferred = false
            session.stoppedAt = nil
            session.state = .failed
            session.unread = true
            session.message = event.message
        case .sessionEnd:
            session.state = .ended
            session.unread = false
            session.runningAgents = []
            session.stopDeferred = false
            session.stoppedAt = nil
        case .other:
            break
        }

        if session.state == .needsYou, !wasWaiting {
            session.waitingSince = event.sentAt
            session.waitingAgent = event.agentID
            session.remindedWait = false
        } else if session.state != .needsYou, wasWaiting {
            if let since = session.waitingSince { session.turnWaited += max(event.sentAt.timeIntervalSince(since), 0) }
            session.waitingSince = nil
            session.waitingAgent = nil
        }

        sessions[session.id] = session
        return session
    }

    /// A session whose Claude Code process is gone without a SessionEnd, as when its terminal tab was closed.
    public mutating func markEnded(_ id: String, at date: Date) {
        guard var session = sessions[id], session.state != .ended else { return }
        session.state = .ended
        session.unread = false
        session.waitingSince = nil
        session.waitingAgent = nil
        session.runningAgents = []
        session.stopDeferred = false
        session.stoppedAt = nil
        session.flaggedQuiet = false
        session.updatedAt = max(session.updatedAt, date)
        sessions[id] = session
    }

    /// Finishes the turns whose main thread stopped at least `stopGrace` (`backgroundGrace` for sessions with
    /// background agents) ago with no subagent started since.
    /// Returns each finished session as it was before and after; the turn ended at `before.stoppedAt`.
    public mutating func finishPendingStops(now: Date) -> [(before: Session, after: Session)] {
        var finished: [(before: Session, after: Session)] = []
        for (id, before) in sessions {
            guard before.stopDeferred, before.runningAgents.isEmpty, let stoppedAt = before.stoppedAt,
                  now.timeIntervalSince(stoppedAt) >= (before.usesBackgroundAgents ? Self.backgroundGrace : Self.stopGrace),
                  before.state != .ended else { continue }
            var after = before
            after.stopDeferred = false
            after.stoppedAt = nil
            after.state = .done
            after.unread = true
            after.message = nil
            if before.state == .needsYou {
                if let since = before.waitingSince { after.turnWaited += max(stoppedAt.timeIntervalSince(since), 0) }
                after.waitingSince = nil
                after.waitingAgent = nil
            }
            sessions[id] = after
            finished.append((before, after))
        }
        return finished.sorted { $0.after.id < $1.after.id }
    }

    public mutating func markReminded(_ id: String) {
        sessions[id]?.remindedWait = true
    }

    public mutating func markQuiet(_ id: String) {
        sessions[id]?.flaggedQuiet = true
    }

    public mutating func setPreview(_ preview: String, for id: String) {
        sessions[id]?.preview = preview
    }

    public mutating func setTitle(_ title: String, for id: String) {
        sessions[id]?.title = title
    }

    public mutating func markSeen(_ id: String) {
        sessions[id]?.unread = false
    }

    public mutating func markAllSeen() {
        for id in sessions.keys { sessions[id]?.unread = false }
    }

    public mutating func removeEnded() {
        sessions = sessions.filter { $0.value.state != .ended }
    }

    public mutating func prune(now: Date) {
        sessions = sessions.filter { _, session in
            let age = now.timeIntervalSince(session.updatedAt)
            if session.state == .ended { return age < Self.endedRetention }
            return age < Self.inactiveRetention
        }
        if sessions.count > Self.limit {
            let keep = Set(ordered.prefix(Self.limit).map(\.id))
            sessions = sessions.filter { keep.contains($0.key) }
        }
    }
}
