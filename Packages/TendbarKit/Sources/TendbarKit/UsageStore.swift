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

public struct AccountUsage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    public var updatedAt: Date

    public var configDirectory: String? {
        id.isEmpty ? nil : id
    }
}

public struct UsageStore: Codable, Sendable, Equatable {
    public private(set) var accounts: [String: AccountUsage] = [:]

    public init() {}

    public var ordered: [AccountUsage] {
        accounts.values.sorted { $0.id < $1.id }
    }

    public static func accountKey(configDirectory: String?) -> String {
        guard let configDirectory, !configDirectory.isEmpty else { return "" }
        let standardized = URL(fileURLWithPath: configDirectory).standardizedFileURL.path
        let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        return standardized == defaultDirectory ? "" : standardized
    }

    @discardableResult
    public mutating func apply(_ envelope: HookEnvelope) -> Bool {
        guard envelope.isStatusLine,
              let input = try? JSONDecoder().decode(StatusLineInput.self, from: Data(envelope.raw.utf8)),
              let limits = input.rateLimits
        else { return false }
        let key = Self.accountKey(configDirectory: envelope.terminal.configDirectory)
        accounts[key] = AccountUsage(
            id: key,
            fiveHour: limits.fiveHour?.window,
            sevenDay: limits.sevenDay?.window,
            updatedAt: envelope.sentAt
        )
        return true
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
    public static func email(configDirectory: String?) -> String? {
        let url = configDirectory.map { URL(fileURLWithPath: $0).appendingPathComponent(".claude.json") }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any]
        else { return nil }
        return account["emailAddress"] as? String
    }
}
