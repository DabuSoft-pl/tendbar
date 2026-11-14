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

    public static let fiveHourLength: TimeInterval = 5 * 60 * 60
    public static let sevenDayLength: TimeInterval = 7 * 24 * 60 * 60

    /// The share of the window that has passed, as a percentage: where usage would be at an even pace.
    public func evenPace(at now: Date, length: TimeInterval) -> Double? {
        guard now < resetsAt, length > 0 else { return nil }
        let elapsed = length - resetsAt.timeIntervalSince(now)
        return min(max(elapsed / length * 100, 0), 100)
    }

    /// When the limit runs out if usage keeps the pace it had at the reading, or nil when it lasts until the reset.
    /// Readings from the first 5% of a window say too little about the pace and give nil too.
    public func runsOut(readAt: Date, now: Date, length: TimeInterval) -> Date? {
        guard now < resetsAt, usedPercentage > 0, usedPercentage < 100 else { return nil }
        let elapsed = length - resetsAt.timeIntervalSince(readAt)
        guard elapsed >= length * 0.05 else { return nil }
        let date = readAt.addingTimeInterval((100 - usedPercentage) / (usedPercentage / elapsed))
        return date < resetsAt && date > now ? date : nil
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
    /// The Claude Code session whose status line sent it.
    public var sessionID: String?
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    public var readAt: Date

    public init(
        configDirectory: String?,
        sessionID: String? = nil,
        fiveHour: LimitWindow?,
        sevenDay: LimitWindow?,
        readAt: Date
    ) {
        self.configDirectory = configDirectory
        self.sessionID = sessionID
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

    /// The known account of the reading's profile whose weekly window, or else five-hour window, resets at the same
    /// moment. Every account has its own reset times, so this tells accounts apart even when sessions signed in to
    /// two of them run side by side, as after switching accounts while older sessions keep going.
    public func account(matching reading: UsageReading) -> AccountUsage? {
        let directory = Self.accountKey(configDirectory: reading.configDirectory)
        let candidates = accounts.values.filter { Self.accountKey(configDirectory: $0.configDirectory) == directory }
        if let resets = reading.sevenDay?.resetsAt,
           let match = candidates.first(where: { $0.sevenDay?.resetsAt == resets }) {
            return match
        }
        if let resets = reading.fiveHour?.resetsAt,
           let match = candidates.first(where: { $0.fiveHour?.resetsAt == resets }) {
            return match
        }
        return nil
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
