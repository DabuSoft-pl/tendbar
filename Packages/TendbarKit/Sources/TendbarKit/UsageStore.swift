import Foundation

public struct LimitWindow: Codable, Sendable, Equatable {
    public var usedPercentage: Double
    public var resetsAt: Date

    public init(usedPercentage: Double, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    public func percentage(at now: Date) -> Double {
        now >= resetsAt ? 0 : min(max(usedPercentage, 0), 100)
    }
}

public struct ScopedWindow: Codable, Sendable, Equatable {
    public var name: String
    public var window: LimitWindow
}

public enum UsageSource: String, Codable, Sendable {
    case statusLine
    case claudeSwap
}

public struct AccountUsage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var configDirectory: String?
    public var email: String?
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    public var scoped: [ScopedWindow]?
    public var updatedAt: Date
    public var source: UsageSource?
}

public struct UsageStore: Codable, Sendable, Equatable {
    public private(set) var accounts: [String: AccountUsage] = [:]

    public init() {}

    public var ordered: [AccountUsage] {
        accounts.values.sorted { ($0.email ?? $0.id).lowercased() == ($1.email ?? $1.id).lowercased()
            ? $0.id < $1.id
            : ($0.email ?? $0.id).lowercased() < ($1.email ?? $1.id).lowercased()
        }
    }

    public static func accountKey(configDirectory: String?) -> String {
        guard let configDirectory, !configDirectory.isEmpty else { return "" }
        let standardized = URL(fileURLWithPath: configDirectory).standardizedFileURL.path
        let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        return standardized == defaultDirectory ? "" : standardized
    }

    public static func key(configDirectory: String?, email: String?) -> String {
        let directory = accountKey(configDirectory: configDirectory)
        guard let email, !email.isEmpty else { return directory }
        return directory + "|" + email.lowercased()
    }

    @discardableResult
    public mutating func apply(_ envelope: HookEnvelope, email: String? = nil) -> Bool {
        guard envelope.isStatusLine,
              let input = try? JSONDecoder().decode(StatusLineInput.self, from: Data(envelope.raw.utf8)),
              let limits = input.rateLimits
        else { return false }
        let directory = Self.accountKey(configDirectory: envelope.terminal.configDirectory)
        let key = Self.key(configDirectory: envelope.terminal.configDirectory, email: email)
        merge(AccountUsage(
            id: key,
            configDirectory: directory.isEmpty ? nil : directory,
            email: email,
            fiveHour: limits.fiveHour?.window,
            sevenDay: limits.sevenDay?.window,
            scoped: nil,
            updatedAt: envelope.sentAt,
            source: .statusLine
        ))
        return true
    }

    @discardableResult
    public mutating func merge(_ reading: AccountUsage) -> Bool {
        if let current = accounts[reading.id], current.updatedAt > reading.updatedAt { return false }
        var reading = reading
        if reading.scoped == nil { reading.scoped = accounts[reading.id]?.scoped }
        guard accounts[reading.id] != reading else { return false }
        accounts[reading.id] = reading
        return true
    }

    public mutating func remove(_ id: String) {
        accounts[id] = nil
    }
}

struct StatusLineInput: Decodable {
    struct Limits: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    struct Window: Decodable {
        let usedPercentage: Double?
        let resetsAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }

        var window: LimitWindow? {
            guard let usedPercentage, let resetsAt else { return nil }
            return LimitWindow(usedPercentage: usedPercentage, resetsAt: Date(timeIntervalSince1970: resetsAt))
        }
    }

    let rateLimits: Limits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

public enum UsagePersistence {
    public static func load(from url: URL = TendbarPaths.usage) -> UsageStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? HookEnvelope.decoder.decode(UsageStore.self, from: data)
        else { return UsageStore() }
        return store
    }

    public static func save(_ store: UsageStore, to url: URL = TendbarPaths.usage) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HookEnvelope.encoder.encode(store).write(to: url, options: .atomic)
    }
}

public enum ClaudeAccount {
    public static func configFile(configDirectory: String?) -> URL {
        configDirectory.map { URL(fileURLWithPath: $0).appendingPathComponent(".claude.json") }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    public static func email(configDirectory: String?) -> String? {
        email(in: configFile(configDirectory: configDirectory))
    }

    public static func email(in url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any]
        else { return nil }
        return account["emailAddress"] as? String
    }
}


public final class AccountEmailCache {
    private var entries: [String: (modified: Date, email: String?)] = [:]

    public init() {}

    public func email(configDirectory: String?) -> String? {
        let url = ClaudeAccount.configFile(configDirectory: configDirectory)
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard let modified else { return nil }
        if let entry = entries[url.path], entry.modified == modified { return entry.email }
        let email = ClaudeAccount.email(in: url)
        entries[url.path] = (modified, email)
        return email
    }
}
