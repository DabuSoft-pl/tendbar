import TendbarDomain

/// Output boundary: use cases hand the new session state to whoever presents it.
@MainActor
public protocol SessionsOutput: AnyObject {
    func show(_ sessions: SessionStore)
}

/// Output boundary for the day by day activity.
@MainActor
public protocol ActivityOutput: AnyObject {
    func show(_ activity: ActivityStats)
}

/// Output boundary for limit readings.
@MainActor
public protocol UsageOutput: AnyObject {
    func show(_ usage: UsageStore)
}
