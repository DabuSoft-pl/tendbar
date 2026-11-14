import Foundation

/// One day of work with Claude: finished turns, the time Claude spent on them and the time it waited for you.
public struct DayActivity: Sendable, Equatable {
    public var turns = 0
    /// Turn time without the waits inside it.
    public var workSeconds: TimeInterval = 0
    public var waits = 0
    public var waitSeconds: TimeInterval = 0
    public var longestWait: TimeInterval = 0
    public var longestWaitFolder: String?
    public var longestTurn: TimeInterval = 0
    public var longestTurnFolder: String?

    public init() {}

    public var isEmpty: Bool {
        turns == 0 && waits == 0
    }

    /// Adds another day's numbers, for a week's total. The longest turn and wait stay the longest of the two.
    public mutating func add(_ other: DayActivity) {
        turns += other.turns
        workSeconds += other.workSeconds
        waits += other.waits
        waitSeconds += other.waitSeconds
        if other.longestWait > longestWait {
            longestWait = other.longestWait
            longestWaitFolder = other.longestWaitFolder
        }
        if other.longestTurn > longestTurn {
            longestTurn = other.longestTurn
            longestTurnFolder = other.longestTurnFolder
        }
    }
}

/// One day of a week view: the day's start and its numbers, empty when nothing happened.
public struct DatedActivity: Sendable, Equatable, Identifiable {
    public let day: Date
    public let activity: DayActivity

    public init(day: Date, activity: DayActivity) {
        self.day = day
        self.activity = activity
    }

    public var id: Date { day }
}

/// Day by day activity, kept for a month. Filled from session changes, never from prompts or replies.
public struct ActivityStats: Sendable, Equatable {
    public static let keptDays = 31
    /// Longer stretches are a session left open overnight, not a wait or a turn worth counting.
    public static let longestCounted: TimeInterval = 12 * 60 * 60

    public private(set) var days: [String: DayActivity]

    public init(days: [String: DayActivity] = [:]) {
        self.days = days
    }

    public static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func day(of date: Date, calendar: Calendar) -> DayActivity {
        days[Self.key(for: date, calendar: calendar)] ?? DayActivity()
    }

    /// Counts a wait that just ended and a turn that just finished. Returns whether anything was counted.
    @discardableResult
    public mutating func record(previous: Session?, current: Session, at date: Date, calendar: Calendar) -> Bool {
        let key = Self.key(for: date, calendar: calendar)
        var day = days[key] ?? DayActivity()
        var counted = false
        let folder = current.folderName

        if let previous, previous.state == .needsYou, current.state != .needsYou, let since = previous.waitingSince {
            let wait = date.timeIntervalSince(since)
            if wait >= 0, wait <= Self.longestCounted {
                day.waits += 1
                day.waitSeconds += wait
                if wait > day.longestWait {
                    day.longestWait = wait
                    day.longestWaitFolder = folder
                }
                counted = true
            }
        }

        let ended = current.state == .done || current.state == .failed
        let wasRunning = previous?.state == .working || previous?.state == .needsYou
        if ended, wasRunning, let start = current.turnStartedAt {
            let turn = date.timeIntervalSince(start)
            if turn >= 0, turn <= Self.longestCounted {
                let work = max(turn - current.turnWaited, 0)
                day.turns += 1
                day.workSeconds += work
                if work > day.longestTurn {
                    day.longestTurn = work
                    day.longestTurnFolder = folder
                }
                counted = true
            }
        }

        if counted { days[key] = day }
        return counted
    }

    /// The `count` days up to and including the day of `date`, oldest first, so a week has no gaps.
    public func days(endingAt date: Date, count: Int = 7, calendar: Calendar) -> [DatedActivity] {
        let today = calendar.startOfDay(for: date)
        return (0..<max(count, 0)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map {
                DatedActivity(day: $0, activity: day(of: $0, calendar: calendar))
            }
        }
    }

    /// The numbers of those days added up.
    public func total(endingAt date: Date, count: Int = 7, calendar: Calendar) -> DayActivity {
        days(endingAt: date, count: count, calendar: calendar).reduce(into: DayActivity()) { $0.add($1.activity) }
    }

    public mutating func prune(now: Date, calendar: Calendar) {
        guard let oldest = calendar.date(byAdding: .day, value: -(Self.keptDays - 1), to: now) else { return }
        let floor = Self.key(for: oldest, calendar: calendar)
        days = days.filter { $0.key >= floor }
    }
}
