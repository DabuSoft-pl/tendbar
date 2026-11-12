import Foundation

public enum HookInstallerError: Error, Equatable {
    case settingsNotAnObject
    case unexpectedHooksFormat(String)
}

public struct HookInstaller: Sendable {
    public enum Status: Equatable, Sendable {
        case connected
        case outdated
        case disconnected
    }

    public static let marker = "tendbar-hook"
    public static let events = [
        "SessionStart", "UserPromptSubmit", "Notification", "PermissionRequest",
        "PostToolUse", "Stop", "StopFailure", "SessionEnd",
    ]
    public static let timeoutSeconds = 3
    public static let backupLimit = 5

    public let settingsURL: URL
    public let hookPath: String

    public init(settingsURL: URL, hookPath: String) {
        self.settingsURL = settingsURL
        self.hookPath = hookPath
    }

    public static func settingsURL(configDirectory: String? = nil) -> URL {
        let base = configDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        return base.appendingPathComponent("settings.json")
    }

    public func status() throws -> Status {
        let commands = Self.ourCommands(in: try load())
        if commands.isEmpty { return .disconnected }
        let expected = Self.command(for: hookPath)
        let complete = Self.events.allSatisfy { commands[$0] == [expected] }
        return complete && commands.count == Self.events.count ? .connected : .outdated
    }

    @discardableResult
    public func connect(now: Date = Date()) throws -> URL? {
        let settings = try Self.addingHooks(
            to: Self.removingOurHooks(from: try load()),
            command: Self.command(for: hookPath)
        )
        let backup = try backupIfPresent(now: now)
        try write(settings)
        return backup
    }

    @discardableResult
    public func disconnect(now: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let settings = Self.removingOurHooks(from: try load())
        let backup = try backupIfPresent(now: now)
        try write(settings)
        return backup
    }

    static func command(for path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains(marker) == true
    }

    static func ourCommands(in settings: [String: Any]) -> [String: [String]] {
        guard let hooks = settings["hooks"] as? [String: Any] else { return [:] }
        var result: [String: [String]] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let commands = groups
                .compactMap { $0["hooks"] as? [[String: Any]] }
                .joined()
                .filter(isOurs)
                .compactMap { $0["command"] as? String }
            if !commands.isEmpty { result[event] = commands }
        }
        return result
    }

    static func removingOurHooks(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let remaining = entries.filter { !isOurs($0) }
                if remaining.count == entries.count { return group }
                if remaining.isEmpty { return nil }
                var copy = group
                copy["hooks"] = remaining
                return copy
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        var result = settings
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    static func addingHooks(to settings: [String: Any], command: String) throws -> [String: Any] {
        var hooks: [String: Any]
        switch settings["hooks"] {
        case nil: hooks = [:]
        case let existing as [String: Any]: hooks = existing
        default: throw HookInstallerError.unexpectedHooksFormat("hooks")
        }
        for event in events {
            var groups: [[String: Any]]
            switch hooks[event] {
            case nil: groups = []
            case let existing as [[String: Any]]: groups = existing
            default: throw HookInstallerError.unexpectedHooksFormat(event)
            }
            let entry: [String: Any] = ["type": "command", "command": command, "timeout": timeoutSeconds]
            groups.append(["hooks": [entry]])
            hooks[event] = groups
        }
        var result = settings
        result["hooks"] = hooks
        return result
    }

    private var resolvedURL: URL {
        settingsURL.resolvingSymlinksInPath()
    }

    func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else { return [:] }
        let data = try Data(contentsOf: resolvedURL)
        if data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookInstallerError.settingsNotAnObject
        }
        return object
    }

    func write(_ settings: [String: Any]) throws {
        let url = resolvedURL
        let manager = FileManager.default
        let permissions = (try? manager.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data + Data("\n".utf8)).write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: permissions ?? NSNumber(value: 0o600)], ofItemAtPath: url.path)
    }

    func backupIfPresent(now: Date) throws -> URL? {
        let source = resolvedURL
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let prefix = source.lastPathComponent + ".tendbar-backup-"
        let directory = source.deletingLastPathComponent()
        let backup = directory.appendingPathComponent(prefix + formatter.string(from: now))
        if manager.fileExists(atPath: backup.path) { try manager.removeItem(at: backup) }
        try manager.copyItem(at: source, to: backup)
        let old = try manager.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(prefix) }
            .sorted(by: >)
            .dropFirst(Self.backupLimit)
        for name in old {
            try? manager.removeItem(at: directory.appendingPathComponent(name))
        }
        return backup
    }
}
