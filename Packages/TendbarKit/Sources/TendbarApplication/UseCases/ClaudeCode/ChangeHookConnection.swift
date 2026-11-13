import TendbarDomain

@MainActor
public final class ChangeHookConnection {
    public enum Change: Sendable {
        case connect
        case disconnect
    }

    private let connector: HookConnecting?

    public init(connector: HookConnecting?) {
        self.connector = connector
    }

    public func execute(_ change: Change, configDirectory: String? = nil) throws {
        guard let connector else { return }
        switch change {
        case .connect: try connector.connect(configDirectory: configDirectory)
        case .disconnect: try connector.disconnect(configDirectory: configDirectory)
        }
    }
}
