import Foundation

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case idle
    case working
    case needsYou
    case done
    case failed
    case ended
}

public struct Session: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var cwd: String?
    public var transcriptPath: String?
    public var terminal: TerminalContext
    public var state: SessionState
    public var startedAt: Date
    public var updatedAt: Date
    public var unread: Bool
    public var message: String?
    public var preview: String?

    public var folderName: String {
        cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? String(id.prefix(8))
    }

    public var configDirectory: String? {
        terminal.configDirectory
    }
}

public struct SessionStore: Codable, Sendable, Equatable {
    public static let attentionNotifications: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]
    public static let endedRetention: TimeInterval = 24 * 60 * 60
    public static let inactiveRetention: TimeInterval = 7 * 24 * 60 * 60
    public static let limit = 100

    public private(set) var sessions: [String: Session] = [:]

    public init() {}

    public var ordered: [Session] {
        sessions.values.sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
    }

    public var needsYouCount: Int {
        sessions.values.filter { $0.state == .needsYou }.count
    }

    public func count(of state: SessionState) -> Int {
        sessions.values.filter { $0.state == state }.count
    }

    @discardableResult
    public mutating func apply(_ payload: HookPayload, envelope: HookEnvelope) -> Session {
        var session = sessions[payload.sessionID] ?? Session(
            id: payload.sessionID,
            terminal: envelope.terminal,
            state: .idle,
            startedAt: envelope.sentAt,
            updatedAt: envelope.sentAt,
            unread: false
        )
        session.cwd = payload.cwd ?? session.cwd
        session.transcriptPath = payload.transcriptPath ?? session.transcriptPath
        session.terminal = envelope.terminal
        session.updatedAt = max(session.updatedAt, envelope.sentAt)

        switch payload.event {
        case "SessionStart":
            if session.state == .ended { session.state = .idle }
        case "UserPromptSubmit":
            session.state = .working
            session.unread = false
            session.message = nil
        case "PostToolUse":
            if session.state == .needsYou {
                session.state = .working
                session.unread = false
                session.message = nil
            }
        case "PermissionRequest":
            session.state = .needsYou
            session.unread = true
        case "Notification":
            if let type = payload.notificationType, !Self.attentionNotifications.contains(type) { break }
            if session.state != .done { session.state = .needsYou }
            session.unread = true
            session.message = payload.message ?? session.message
        case "Stop":
            session.state = .done
            session.unread = true
            session.message = nil
        case "StopFailure":
            session.state = .failed
            session.unread = true
            session.message = payload.message
        case "SessionEnd":
            session.state = .ended
            session.unread = false
        default:
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

public enum SessionPersistence {
    public static func load(from url: URL = TendbarPaths.sessions) -> SessionStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? HookEnvelope.decoder.decode(SessionStore.self, from: data)
        else { return SessionStore() }
        return store
    }

    public static func save(_ store: SessionStore, to url: URL = TendbarPaths.sessions) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HookEnvelope.encoder.encode(store).write(to: url, options: .atomic)
    }
}
