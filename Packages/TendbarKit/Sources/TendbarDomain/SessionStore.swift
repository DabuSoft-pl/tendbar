import Foundation

/// All known sessions and the rules for how hook events move them between states.
public struct SessionStore: Sendable, Equatable {
    public static let endedRetention: TimeInterval = 24 * 60 * 60
    public static let inactiveRetention: TimeInterval = 7 * 24 * 60 * 60
    public static let limit = 100

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

        switch event.kind {
        case .sessionStart:
            if session.state == .ended { session.state = .idle }
        case .userPromptSubmit:
            session.state = .working
            session.turnStartedAt = event.sentAt
            session.unread = false
            session.message = nil
        case .postToolUse:
            if session.state == .needsYou {
                session.state = .working
                session.unread = false
                session.message = nil
            }
        case .permissionRequest:
            session.state = .needsYou
            session.unread = true
        case .notification:
            guard event.asksForAttention else { break }
            if session.state != .done { session.state = .needsYou }
            session.unread = true
            session.message = event.message ?? session.message
        case .stop:
            session.state = .done
            session.unread = true
            session.message = nil
        case .stopFailure:
            session.state = .failed
            session.unread = true
            session.message = event.message
        case .sessionEnd:
            session.state = .ended
            session.unread = false
        case .other:
            break
        }

        sessions[session.id] = session
        return session
    }

    public mutating func setPreview(_ preview: String, for id: String) {
        sessions[id]?.preview = preview
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
