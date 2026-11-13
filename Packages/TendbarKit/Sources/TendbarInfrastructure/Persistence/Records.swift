import Foundation
import TendbarDomain

// Storage shapes of `sessions.json` and `usage.json`. The domain types know nothing about JSON;
// these records keep the file format stable while the domain is free to change.

struct SessionStoreRecord: Codable {
    var sessions: [String: SessionRecord]

    init(_ store: SessionStore) {
        sessions = store.sessions.mapValues(SessionRecord.init)
    }

    var store: SessionStore {
        SessionStore(sessions: sessions.values.map(\.session))
    }
}

struct SessionRecord: Codable {
    var id: String
    var cwd: String?
    var transcriptPath: String?
    var terminal: TerminalRecord
    var state: String
    var startedAt: Date
    var updatedAt: Date
    var turnStartedAt: Date?
    var waitingSince: Date?
    var turnWaited: TimeInterval?
    var remindedWait: Bool?
    var flaggedQuiet: Bool?
    var waitingAgent: String?
    var unread: Bool
    var message: String?
    var preview: String?

    init(_ session: Session) {
        id = session.id
        cwd = session.cwd
        transcriptPath = session.transcriptPath
        terminal = TerminalRecord(session.terminal)
        state = session.state.rawValue
        startedAt = session.startedAt
        updatedAt = session.updatedAt
        turnStartedAt = session.turnStartedAt
        waitingSince = session.waitingSince
        turnWaited = session.turnWaited
        remindedWait = session.remindedWait
        flaggedQuiet = session.flaggedQuiet
        waitingAgent = session.waitingAgent
        unread = session.unread
        message = session.message
        preview = session.preview
    }

    var session: Session {
        Session(
            id: id,
            cwd: cwd,
            transcriptPath: transcriptPath,
            terminal: terminal.context,
            state: SessionState(rawValue: state) ?? .idle,
            startedAt: startedAt,
            updatedAt: updatedAt,
            turnStartedAt: turnStartedAt,
            waitingSince: waitingSince,
            turnWaited: turnWaited ?? 0,
            remindedWait: remindedWait ?? false,
            flaggedQuiet: flaggedQuiet ?? false,
            waitingAgent: waitingAgent,
            unread: unread,
            message: message,
            preview: preview
        )
    }
}

struct UsageStoreRecord: Codable {
    var accounts: [String: AccountUsageRecord]

    init(_ store: UsageStore) {
        accounts = store.accounts.mapValues(AccountUsageRecord.init)
    }

    var store: UsageStore {
        UsageStore(accounts: accounts.values.map(\.account))
    }
}

struct AccountUsageRecord: Codable {
    struct Window: Codable {
        var usedPercentage: Double
        var resetsAt: Date
    }

    var id: String
    var configDirectory: String?
    var email: String?
    var fiveHour: Window?
    var sevenDay: Window?
    var updatedAt: Date

    init(_ account: AccountUsage) {
        id = account.id
        configDirectory = account.configDirectory
        email = account.email
        fiveHour = account.fiveHour.map { Window(usedPercentage: $0.usedPercentage, resetsAt: $0.resetsAt) }
        sevenDay = account.sevenDay.map { Window(usedPercentage: $0.usedPercentage, resetsAt: $0.resetsAt) }
        updatedAt = account.updatedAt
    }

    var account: AccountUsage {
        AccountUsage(
            id: id,
            configDirectory: configDirectory,
            email: email,
            fiveHour: fiveHour.map { LimitWindow(usedPercentage: $0.usedPercentage, resetsAt: $0.resetsAt) },
            sevenDay: sevenDay.map { LimitWindow(usedPercentage: $0.usedPercentage, resetsAt: $0.resetsAt) },
            updatedAt: updatedAt
        )
    }
}

/// `activity.json`: per day counts and durations, with only the folder name of the longest wait and turn.
struct ActivityRecord: Codable {
    struct Day: Codable {
        var turns: Int
        var workSeconds: Double
        var waits: Int
        var waitSeconds: Double
        var longestWait: Double
        var longestWaitFolder: String?
        var longestTurn: Double
        var longestTurnFolder: String?
    }

    var days: [String: Day]

    init(_ stats: ActivityStats) {
        days = stats.days.mapValues {
            Day(
                turns: $0.turns, workSeconds: $0.workSeconds, waits: $0.waits, waitSeconds: $0.waitSeconds,
                longestWait: $0.longestWait, longestWaitFolder: $0.longestWaitFolder,
                longestTurn: $0.longestTurn, longestTurnFolder: $0.longestTurnFolder
            )
        }
    }

    var stats: ActivityStats {
        ActivityStats(days: days.mapValues {
            var day = DayActivity()
            day.turns = $0.turns
            day.workSeconds = $0.workSeconds
            day.waits = $0.waits
            day.waitSeconds = $0.waitSeconds
            day.longestWait = $0.longestWait
            day.longestWaitFolder = $0.longestWaitFolder
            day.longestTurn = $0.longestTurn
            day.longestTurnFolder = $0.longestTurnFolder
            return day
        })
    }
}
