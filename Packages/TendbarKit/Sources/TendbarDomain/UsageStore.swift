import Foundation

public struct LimitWindow: Sendable, Equatable {
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

public struct AccountUsage: Sendable, Equatable, Identifiable {
    public var id: String
    public var configDirectory: String?
    public var email: String?
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    public var updatedAt: Date

    public init(
        id: String,
        configDirectory: String? = nil,
        email: String? = nil,
        fiveHour: LimitWindow? = nil,
        sevenDay: LimitWindow? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.configDirectory = configDirectory
        self.email = email
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
    }

    public func highestPercentage(at now: Date) -> Double {
        [fiveHour, sevenDay].compactMap { $0?.percentage(at: now) }.max() ?? 0
    }
}

/// One status line reading: the limits of whichever account a Claude Code profile was signed in to.
public struct UsageReading: Sendable, Equatable {
    public var configDirectory: String?
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    public var readAt: Date

    public init(configDirectory: String?, fiveHour: LimitWindow?, sevenDay: LimitWindow?, readAt: Date) {
        self.configDirectory = configDirectory
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.readAt = readAt
    }
}

public struct UsageStore: Sendable, Equatable {
    public private(set) var accounts: [String: AccountUsage]

    public init(accounts: [AccountUsage] = []) {
        self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }

    public var ordered: [AccountUsage] {
        accounts.values.sorted { ($0.email ?? $0.id).lowercased() == ($1.email ?? $1.id).lowercased()
            ? $0.id < $1.id
            : ($0.email ?? $0.id).lowercased() < ($1.email ?? $1.id).lowercased()
        }
    }

    /// The account read most recently is the one Claude Code is using now.
    public var current: AccountUsage? {
        accounts.values.max { $0.updatedAt < $1.updatedAt }
    }

    public var currentFirst: [AccountUsage] {
        let current = current?.id
        return ordered.filter { $0.id == current } + ordered.filter { $0.id != current }
    }

    public func currentLimit(at now: Date) -> Double {
        current?.highestPercentage(at: now) ?? 0
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

    /// Files a reading under the account signed in when it was taken. A missing window means it was reset.
    @discardableResult
    public mutating func record(_ reading: UsageReading, email: String?) -> Bool {
        let directory = Self.accountKey(configDirectory: reading.configDirectory)
        return merge(AccountUsage(
            id: Self.key(configDirectory: reading.configDirectory, email: email),
            configDirectory: directory.isEmpty ? nil : directory,
            email: email,
            fiveHour: reading.fiveHour,
            sevenDay: reading.sevenDay,
            updatedAt: reading.readAt
        ))
    }

    @discardableResult
    public mutating func merge(_ reading: AccountUsage) -> Bool {
        if let current = accounts[reading.id], current.updatedAt > reading.updatedAt { return false }
        guard accounts[reading.id] != reading else { return false }
        accounts[reading.id] = reading
        return true
    }

    public mutating func remove(_ id: String) {
        accounts[id] = nil
    }
}
