import Foundation
import TendbarDomain

/// The terminal a hook ran in, as the hook helper sends it and as `sessions.json` stores it.
public struct TerminalRecord: Codable, Sendable, Equatable {
    public var program: String?
    public var hostBundleID: String?
    public var itermSessionID: String?
    public var terminalSessionID: String?
    public var tty: String?
    public var configDirectory: String?
    public var weztermPane: String?
    public var weztermSocket: String?
    public var kittyWindowID: String?
    public var kittySocket: String?
    public var tmuxPane: String?
    public var tmuxSocket: String?

    public init(_ context: TerminalContext) {
        program = context.program
        hostBundleID = context.hostBundleID
        itermSessionID = context.itermSessionID
        terminalSessionID = context.terminalSessionID
        tty = context.tty
        configDirectory = context.configDirectory
        weztermPane = context.weztermPane
        weztermSocket = context.weztermSocket
        kittyWindowID = context.kittyWindowID
        kittySocket = context.kittySocket
        tmuxPane = context.tmuxPane
        tmuxSocket = context.tmuxSocket
    }

    public var context: TerminalContext {
        TerminalContext(
            program: program,
            hostBundleID: hostBundleID,
            itermSessionID: itermSessionID,
            terminalSessionID: terminalSessionID,
            tty: tty,
            configDirectory: configDirectory,
            weztermPane: weztermPane,
            weztermSocket: weztermSocket,
            kittyWindowID: kittyWindowID,
            kittySocket: kittySocket,
            tmuxPane: tmuxPane,
            tmuxSocket: tmuxSocket
        )
    }
}

extension TerminalContext {
    public static func capture(environment: [String: String], tty: String?) -> TerminalContext {
        TerminalContext(
            program: environment["TERM_PROGRAM"],
            hostBundleID: environment["__CFBundleIdentifier"],
            itermSessionID: environment["ITERM_SESSION_ID"],
            terminalSessionID: environment["TERM_SESSION_ID"],
            tty: tty,
            configDirectory: environment["CLAUDE_CONFIG_DIR"],
            weztermPane: environment["WEZTERM_PANE"],
            weztermSocket: environment["WEZTERM_UNIX_SOCKET"],
            kittyWindowID: environment["KITTY_WINDOW_ID"],
            kittySocket: environment["KITTY_LISTEN_ON"],
            tmuxPane: environment["TMUX_PANE"],
            tmuxSocket: environment["TMUX"].flatMap { $0.split(separator: ",").first.map(String.init) }
        )
    }
}

/// What `tendbar-hook` sends over the socket: the hook input (already redacted) plus where it ran.
public struct HookEnvelope: Codable, Sendable, Equatable {
    public static let statusLineChannel = "statusline"

    public var sentAt: Date
    public var terminal: TerminalRecord
    public var raw: String
    public var channel: String?

    public init(sentAt: Date, terminal: TerminalContext, raw: String, channel: String? = nil) {
        self.sentAt = sentAt
        self.terminal = TerminalRecord(terminal)
        self.raw = raw
        self.channel = channel
    }

    public var isStatusLine: Bool {
        channel == Self.statusLineChannel
    }

    public func payload() throws -> HookPayload {
        try JSONDecoder().decode(HookPayload.self, from: Data(raw.utf8))
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public struct HookPayload: Codable, Sendable, Equatable {
    public var sessionID: String
    public var event: String
    public var cwd: String?
    public var transcriptPath: String?
    public var message: String?
    public var notificationType: String?
    /// `StopFailure` only: the error type (`rate_limit`, `overloaded`, ...) and optional details.
    public var error: String?
    public var errorDetails: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case event = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
        case message
        case notificationType = "notification_type"
        case error
        case errorDetails = "error_details"
    }

    /// A readable line for a failed turn, such as "API overloaded (529 Overloaded)".
    public var failureMessage: String? {
        guard let error else { return nil }
        let title = switch error {
        case "rate_limit": String(localized: "Rate limit")
        case "overloaded": String(localized: "API overloaded")
        case "authentication_failed": String(localized: "Authentication failed")
        case "oauth_org_not_allowed": String(localized: "Organization not allowed")
        case "account_on_hold": String(localized: "Account on hold")
        case "billing_error": String(localized: "Billing problem")
        case "invalid_request": String(localized: "Invalid request")
        case "model_not_found": String(localized: "Model not found")
        case "server_error": String(localized: "API server error")
        case "max_output_tokens": String(localized: "Reply hit the length limit")
        case "cloud_credential_error": String(localized: "Cloud credential error")
        default: String(localized: "API error")
        }
        guard let details = errorDetails?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty else { return title }
        return "\(title) (\(details.prefix(120)))"
    }
}

public enum HookRedaction {
    public static let hookKeys: Set<String> = [
        "session_id", "hook_event_name", "cwd", "transcript_path", "message", "notification_type", "source", "reason",
        "error", "error_details",
    ]
    public static let statusLineKeys: Set<String> = ["session_id", "rate_limits"]

    public static func redact(_ input: Data, statusLine: Bool) -> String {
        let keep = statusLine ? statusLineKeys : hookKeys
        guard let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: object.filter { keep.contains($0.key) }, options: [.sortedKeys])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
