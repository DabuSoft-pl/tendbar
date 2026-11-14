import TendbarDomain

public enum HookConnection: Sendable, Equatable {
    case connected
    case outdated
    case disconnected
}

/// Adds or removes Tendbar's hooks in a Claude Code profile's settings.
@MainActor
public protocol HookConnecting: AnyObject {
    func status(configDirectory: String?) throws -> HookConnection
    func connect(configDirectory: String?) throws
    func disconnect(configDirectory: String?) throws
}

public enum ProfileCreationError: Error, Equatable {
    case invalidName
    case failed(String)
}

@MainActor
public protocol ProfileDirectories: AnyObject {
    /// Creates `~/.claude-<name>` sharing settings with `~/.claude` and returns its path.
    func create(named name: String) throws -> String
}

@MainActor
public protocol AccountEmailResolving: AnyObject {
    func email(configDirectory: String?) -> String?
}

public protocol TranscriptReading: Sendable {
    /// The start of Claude's last reply in a session transcript.
    func lastReplyPreview(at path: String) async -> String?
    /// The latest title Claude Code gave the conversation in its transcript.
    func title(at path: String) async -> String?
}
