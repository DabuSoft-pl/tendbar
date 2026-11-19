import Foundation
import TendbarApplication
import TendbarDomain

/// Runs the shortcut the user picked for an event along with its banner. It goes through the `shortcuts` command
/// without a shell and does not wait for the shortcut to finish.
@MainActor
final class ShortcutTrigger: AlertPresenting {
    /// The `Preferences.eventShortcuts` key of a limit warning; sessions use their `AlertKind` raw value.
    static let limitKey = "limit"
    nonisolated private static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    private let alerts: AlertPresenting
    private let preferences: Preferences

    init(alerts: AlertPresenting, preferences: Preferences) {
        self.alerts = alerts
        self.preferences = preferences
    }

    func present(_ kind: AlertKind, for session: Session, sound: AlertSound) {
        alerts.present(kind, for: session, sound: sound)
        run(kind.rawValue)
    }

    func presentLimit(_ warning: LimitWarning, account: AccountUsage, sound: AlertSound) {
        alerts.presentLimit(warning, account: account, sound: sound)
        run(Self.limitKey)
    }

    func presentLimitReset(_ reset: LimitReset, account: AccountUsage, sound: AlertSound) {
        alerts.presentLimitReset(reset, account: account, sound: sound)
    }

    func presentPermission(_ ask: PermissionAsk, for session: Session, sound: AlertSound) {
        alerts.presentPermission(ask, for: session, sound: sound)
        run(AlertKind.needsYou.rawValue)
    }

    func dismiss(sessionID: String) {
        alerts.dismiss(sessionID: sessionID)
    }

    private func run(_ event: String) {
        guard let name = preferences.eventShortcuts[event] else { return }
        let process = Process()
        process.executableURL = Self.tool
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// The names of the user's shortcuts; empty when the `shortcuts` command fails.
    nonisolated static func names() async -> [String] {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = tool
            process.arguments = ["list"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).sorted()
        }.value
    }
}
