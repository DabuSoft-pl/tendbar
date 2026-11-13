import Foundation

/// Something Claude Code reported about one session, already stripped of the wire format.
public struct HookEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case sessionStart
        case userPromptSubmit
        case postToolUse
        case permissionRequest
        case notification
        case stop
        case stopFailure
        case sessionEnd
        case other(String)

        public init(name: String) {
            switch name {
            case "SessionStart": self = .sessionStart
            case "UserPromptSubmit": self = .userPromptSubmit
            case "PostToolUse": self = .postToolUse
            case "PermissionRequest": self = .permissionRequest
            case "Notification": self = .notification
            case "Stop": self = .stop
            case "StopFailure": self = .stopFailure
            case "SessionEnd": self = .sessionEnd
            default: self = .other(name)
            }
        }
    }

    /// Notification types that mean the user has to act. Others, like `idle_prompt`, are ignored.
    public static let attentionNotifications: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]

    public var sessionID: String
    public var kind: Kind
    public var cwd: String?
    public var transcriptPath: String?
    public var message: String?
    public var notificationType: String?
    public var terminal: TerminalContext
    public var sentAt: Date

    public init(
        sessionID: String,
        kind: Kind,
        cwd: String? = nil,
        transcriptPath: String? = nil,
        message: String? = nil,
        notificationType: String? = nil,
        terminal: TerminalContext = TerminalContext(),
        sentAt: Date
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.message = message
        self.notificationType = notificationType
        self.terminal = terminal
        self.sentAt = sentAt
    }

    public var asksForAttention: Bool {
        notificationType.map(Self.attentionNotifications.contains) ?? true
    }
}
