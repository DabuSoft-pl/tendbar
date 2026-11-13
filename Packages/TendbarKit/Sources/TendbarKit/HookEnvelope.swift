import Foundation

public struct TerminalContext: Codable, Sendable, Equatable {
    public var program: String?
    public var itermSessionID: String?
    public var terminalSessionID: String?
    public var tty: String?
    public var configDirectory: String?

    public init(
        program: String? = nil,
        itermSessionID: String? = nil,
        terminalSessionID: String? = nil,
        tty: String? = nil,
        configDirectory: String? = nil
    ) {
        self.program = program
        self.itermSessionID = itermSessionID
        self.terminalSessionID = terminalSessionID
        self.tty = tty
        self.configDirectory = configDirectory
    }

    public static func capture(environment: [String: String], tty: String?) -> TerminalContext {
        TerminalContext(
            program: environment["TERM_PROGRAM"],
            itermSessionID: environment["ITERM_SESSION_ID"],
            terminalSessionID: environment["TERM_SESSION_ID"],
            tty: tty,
            configDirectory: environment["CLAUDE_CONFIG_DIR"]
        )
    }
}

public struct HookEnvelope: Codable, Sendable, Equatable {
    public static let statusLineChannel = "statusline"

    public var sentAt: Date
    public var terminal: TerminalContext
    public var raw: String
    public var channel: String?

    public init(sentAt: Date, terminal: TerminalContext, raw: String, channel: String? = nil) {
        self.sentAt = sentAt
        self.terminal = terminal
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

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case event = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
        case message
        case notificationType = "notification_type"
    }
}

public enum HookRedaction {
    public static let hookKeys: Set<String> = [
        "session_id", "hook_event_name", "cwd", "transcript_path", "message", "notification_type", "source", "reason",
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
