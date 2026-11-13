/// A permission prompt Claude Code shows in the terminal, as far as Tendbar may show it in a banner: the tool and
/// what it would run or touch. Kept in memory only, never in a file.
public struct PermissionAsk: Sendable, Equatable {
    /// Tells this prompt apart from a later one in the same session, so a stale banner never answers a newer prompt.
    public var id: String
    public var sessionID: String
    public var tool: String
    /// The command, file path or URL, as Claude Code passed it.
    public var detail: String?

    public init(id: String, sessionID: String, tool: String, detail: String? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.tool = tool
        self.detail = detail
    }
}

public enum PermissionDecision: String, Sendable, Codable {
    case allow
    case deny
}
