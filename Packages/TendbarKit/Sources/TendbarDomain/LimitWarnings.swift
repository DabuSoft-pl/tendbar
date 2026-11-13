import Foundation

public struct LimitWarning: Equatable, Sendable {
    public var accountID: String
    public var window: String
    public var threshold: Int
    public var percentage: Double
    public var resetsAt: Date
}

/// A window that warned before and has now reset, so the limit is available again.
public struct LimitReset: Equatable, Sendable {
    public var accountID: String
    public var window: String
    public var resetsAt: Date
}

public enum LimitWarnings {
    public static let thresholds = [80, 90]
    public static let fiveHour = "five_hour"
    public static let sevenDay = "seven_day"

    public static func key(accountID: String, window: String, resetsAt: Date, threshold: Int) -> String {
        "\(accountID)|\(window)|\(Int(resetsAt.timeIntervalSince1970))|\(threshold)"
    }

    public static func windows(of account: AccountUsage) -> [(name: String, window: LimitWindow)] {
        var result: [(String, LimitWindow)] = []
        if let window = account.fiveHour { result.append((fiveHour, window)) }
        if let window = account.sevenDay { result.append((sevenDay, window)) }
        return result
    }

    public static func pending(for account: AccountUsage, now: Date, fired: Set<String>) -> [LimitWarning] {
        windows(of: account).compactMap { name, window in
            guard now < window.resetsAt else { return nil }
            let percentage = window.percentage(at: now)
            guard let threshold = thresholds.last(where: { percentage >= Double($0) }),
                  !fired.contains(key(accountID: account.id, window: name, resetsAt: window.resetsAt, threshold: threshold))
            else { return nil }
            return LimitWarning(accountID: account.id, window: name, threshold: threshold, percentage: percentage, resetsAt: window.resetsAt)
        }
    }

    public static func keys(firing warning: LimitWarning) -> [String] {
        thresholds.filter { $0 <= warning.threshold }.map {
            key(accountID: warning.accountID, window: warning.window, resetsAt: warning.resetsAt, threshold: $0)
        }
    }

    public static func resetKey(accountID: String, window: String, resetsAt: Date) -> String {
        "\(accountID)|\(window)|\(Int(resetsAt.timeIntervalSince1970))|reset"
    }

    /// Windows that crossed a warning threshold and have reset since, not announced yet. Only the last reading of a
    /// window is known, so a reset shows up once its time has passed, even when no new reading came in.
    public static func resets(for account: AccountUsage, now: Date, fired: Set<String>) -> [LimitReset] {
        windows(of: account).compactMap { name, window in
            guard now >= window.resetsAt,
                  fired.contains(key(accountID: account.id, window: name, resetsAt: window.resetsAt, threshold: thresholds[0])),
                  !fired.contains(resetKey(accountID: account.id, window: name, resetsAt: window.resetsAt))
            else { return nil }
            return LimitReset(accountID: account.id, window: name, resetsAt: window.resetsAt)
        }
    }
}
