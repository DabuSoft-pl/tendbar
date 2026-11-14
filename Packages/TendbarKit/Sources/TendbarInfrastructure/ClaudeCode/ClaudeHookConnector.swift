import Foundation
import TendbarApplication

/// Connects profiles by editing their `settings.json` through `HookInstaller`.
@MainActor
public final class ClaudeHookConnector: HookConnecting {
    private let hookPath: String

    public init(hookPath: String) {
        self.hookPath = hookPath
    }

    public func status(configDirectory: String?) throws -> HookConnection {
        switch try installer(configDirectory).status() {
        case .connected: .connected
        case .outdated: .outdated
        case .otherCopy: .otherCopy
        case .helperGone: .helperGone
        case .disconnected: .disconnected
        }
    }

    public func connect(configDirectory: String?) throws {
        _ = try installer(configDirectory).connect()
    }

    public func disconnect(configDirectory: String?) throws {
        _ = try installer(configDirectory).disconnect()
    }

    private func installer(_ configDirectory: String?) -> HookInstaller {
        HookInstaller(settingsURL: HookInstaller.settingsURL(configDirectory: configDirectory), hookPath: hookPath)
    }
}
