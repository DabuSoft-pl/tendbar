import TendbarDomain

/// Output boundary: use cases hand the new session state to whoever presents it.
@MainActor
public protocol SessionsOutput: AnyObject {
    func show(_ sessions: SessionStore)
}

/// Output boundary for limit readings.
@MainActor
public protocol UsageOutput: AnyObject {
    func show(_ usage: UsageStore)
}
