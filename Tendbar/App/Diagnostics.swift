import AppKit
import Foundation
import TendbarApplication
import TendbarDomain

/// A short report for bug reports: versions, the connection and settings. It leaves out folder names, e-mail
/// addresses, messages and paths, so it is safe to paste into a public issue.
@MainActor
enum Diagnostics {
    static func report(_ container: AppContainer) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let sessions = container.sessions.sessions
        let states = SessionState.allCases
            .map { state in "\(state.rawValue) \(sessions.filter { $0.state == state }.count)" }
            .joined(separator: ", ")
        let terminals = Set(sessions.compactMap { $0.terminal.program ?? $0.terminal.hostBundleID }).sorted()
        let preferences = container.preferences
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif

        return [
            "Tendbar \(version) (\(build))",
            "macOS \(macOSVersion), \(architecture)",
            "Language: \(Locale.preferredLanguages.first ?? "?")",
            "Screens: \(NSScreen.screens.count), notch: \(NotchController.hasNotch ? "yes" : "no")",
            "Claude Code hooks: \(connection(container.claudeCode.connection)), helper: \(container.claudeCode.helperAvailable ? "present" : "missing")",
            "Notifications: \(permission(container.system.notificationPermission))",
            "Sessions: \(sessions.count) (\(states))",
            "Terminals: \(terminals.isEmpty ? "none" : terminals.joined(separator: ", "))",
            "Accounts with limits: \(container.usage.accounts.count)",
            "Settings: menu bar \(preferences.menuBarStyle.rawValue), pill \(preferences.notchView ? preferences.pillVisibility.rawValue : "off"), "
                + "usage \(preferences.usageStyle.rawValue), glow \(preferences.edgeGlow), hidden from capture \(preferences.hideFromCapture), "
                + "muted folders \(preferences.mutedFolders.count), event log \(preferences.logEvents), "
                + "desktop banners left to the app \(preferences.leaveDesktopBanners), shortcut \(preferences.nextSessionShortcut.rawValue)\(container.system.shortcutTaken ? " (taken)" : ""), "
                + "update checks \(container.updates.isAvailable ? String(container.updates.checksAutomatically) : "unavailable")",
        ].joined(separator: "\n")
    }

    /// "27.2.1 (26B131)", the same in every language.
    private static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var build = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.osversion", &build, &size, nil, 0)
        let number = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let buildText = String(decoding: build.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
        return buildText.isEmpty ? number : "\(number) (\(buildText))"
    }

    private static func connection(_ connection: HookConnection?) -> String {
        guard let connection else { return "unknown" }
        return "\(connection)"
    }

    private static func permission(_ permission: NotificationPermission) -> String {
        "\(permission)"
    }
}
