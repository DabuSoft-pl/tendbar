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
    /// A PermissionRequest hook may wait for Allow or Deny on a banner. The terminal prompt works meanwhile.
    public static let permissionTimeoutSeconds = 600
    /// How long the hook waits for that answer, a little under its timeout so it always exits on its own.
    public static let permissionWaitSeconds = 590.0
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

    public static let statusLineFlag = "--statusline"
    public static let nextFlag = "--next"

    public func status() throws -> Status {
        let settings = try load()
        let commands = Self.ourCommands(in: settings)
        let statusLine = Self.statusLineCommand(in: settings)
        let wrapped = statusLine.map(Self.isOurs(command:)) == true
        if commands.isEmpty && !wrapped { return .disconnected }
        let expected = Self.command(for: hookPath)
        let timeouts = Self.ourTimeouts(in: settings)
        let complete = Self.events.allSatisfy { commands[$0] == [expected] && timeouts[$0] == [Self.timeout(for: $0)] }
            && commands.count == Self.events.count
        let statusLineCurrent = statusLine?.hasPrefix(expected + " " + Self.statusLineFlag) == true
        return complete && statusLineCurrent ? .connected : .outdated
    }

    @discardableResult
    public func connect(now: Date = Date()) throws -> URL? {
        let settings = try Self.wrappingStatusLine(
            in: Self.addingHooks(to: Self.removingOurHooks(from: try load()), command: Self.command(for: hookPath)),
            hookPath: hookPath
        )
        let backup = try backupIfPresent(now: now)
        try write(settings)
        return backup
    }

    @discardableResult
    public func disconnect(now: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let settings = Self.unwrappingStatusLine(in: Self.removingOurHooks(from: try load()))
        let backup = try backupIfPresent(now: now)
        try write(settings)
        return backup
    }

    public static func statusLineCommand(hookPath: String, next: String?) -> String {
        var command = command(for: hookPath) + " " + statusLineFlag
        if let next, !next.isEmpty {
            command += " " + nextFlag + " " + Data(next.utf8).base64EncodedString()
        }
        return command
    }

    public static func wrappedCommand(in command: String) -> String? {
        guard let range = command.range(of: " \(nextFlag) ", options: .backwards) else { return nil }
        let encoded = command[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func isOurs(command: String) -> Bool {
        command.contains(marker) && command.contains(statusLineFlag)
    }

    static func statusLineCommand(in settings: [String: Any]) -> String? {
        (settings["statusLine"] as? [String: Any])?["command"] as? String
    }

    static func wrappingStatusLine(in settings: [String: Any], hookPath: String) throws -> [String: Any] {
        var result = settings
        switch settings["statusLine"] {
        case nil:
            result["statusLine"] = ["type": "command", "command": statusLineCommand(hookPath: hookPath, next: nil)]
        case var existing as [String: Any]:
            let current = existing["command"] as? String
            let next = current.map { isOurs(command: $0) ? wrappedCommand(in: $0) : $0 } ?? nil
            existing["type"] = "command"
            existing["command"] = statusLineCommand(hookPath: hookPath, next: next)
            result["statusLine"] = existing
        default:
            throw HookInstallerError.unexpectedHooksFormat("statusLine")
        }
        return result
    }

    static func unwrappingStatusLine(in settings: [String: Any]) -> [String: Any] {
        guard var existing = settings["statusLine"] as? [String: Any],
              let current = existing["command"] as? String,
              isOurs(command: current)
        else { return settings }
        var result = settings
        if let next = wrappedCommand(in: current) {
            existing["command"] = next
            result["statusLine"] = existing
        } else {
            result["statusLine"] = nil
        }
        return result
    }

    static func command(for path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains(marker) == true
    }

    static func timeout(for event: String) -> Int {
        event == "PermissionRequest" ? permissionTimeoutSeconds : timeoutSeconds
    }

    static func ourTimeouts(in settings: [String: Any]) -> [String: [Int]] {
        guard let hooks = settings["hooks"] as? [String: Any] else { return [:] }
        var result: [String: [Int]] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let timeouts = groups
                .compactMap { $0["hooks"] as? [[String: Any]] }
                .joined()
                .filter(isOurs)
                .map { ($0["timeout"] as? NSNumber)?.intValue ?? -1 }
            if !timeouts.isEmpty { result[event] = timeouts }
        }
        return result
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
            let entry: [String: Any] = ["type": "command", "command": command, "timeout": timeout(for: event)]
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
