import Foundation
import TendbarApplication

/// Connects profiles by editing their `settings.json` through `HookInstaller`.
@MainActor
public final class ClaudeHookConnector: HookConnecting {
    private let hookPath: String

    public init(hookPath: String) {
        self.hookPath = hookPath
    }

    /// Also re-wraps a statusLine another tool replaced: this runs at launch, on panel open and every 30 s.
    public func status(configDirectory: String?) throws -> HookConnection {
        let installer = installer(configDirectory)
        _ = try? installer.repairStatusLine()
        return switch try installer.status() {
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
