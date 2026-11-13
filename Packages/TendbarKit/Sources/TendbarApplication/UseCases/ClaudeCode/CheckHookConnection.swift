import TendbarDomain

/// Nil when the app has no hook helper to connect.
@MainActor
public final class CheckHookConnection {
    private let connector: HookConnecting?

    public init(connector: HookConnecting?) {
        self.connector = connector
    }

    public func execute(configDirectory: String? = nil) throws -> HookConnection? {
        try connector?.status(configDirectory: configDirectory)
    }
}
