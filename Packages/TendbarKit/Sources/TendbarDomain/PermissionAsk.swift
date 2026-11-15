/// A permission prompt Claude Code shows in the terminal, as far as Tendbar may show it in a banner: the tool and
/// what it would run or touch. Kept in memory only, never in a file.
public struct PermissionAsk: Sendable, Equatable {
    /// Tells this prompt apart from a later one in the same session, so a stale banner never answers a newer prompt.
    public var id: String
    public var sessionID: String
    public var tool: String
    /// The command, file path or URL, as Claude Code passed it.
    public var detail: String?
    /// True only when `detail` is everything the request would do: no cut, and no other field that changes what runs
    /// or what gets written (a file's new content, an MCP tool's arguments). Tendbar offers Allow only then; anything
    /// else is answered in the terminal, which shows the whole request.
    public var shownInFull: Bool

    public init(id: String, sessionID: String, tool: String, detail: String? = nil, shownInFull: Bool = false) {
        self.id = id
        self.sessionID = sessionID
        self.tool = tool
        self.detail = detail
        self.shownInFull = shownInFull
    }

    /// Allow approves the whole request, so it is offered only for a request shown whole. Deny is always safe.
    public func offers(_ decision: PermissionDecision) -> Bool {
        decision == .deny || shownInFull
    }
}

public enum PermissionDecision: String, Sendable, Codable {
    case allow
    case deny
}
