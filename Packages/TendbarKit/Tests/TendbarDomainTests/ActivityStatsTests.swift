import Foundation
import Testing
@testable import TendbarDomain

@Suite struct ActivityStatsTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let minute: TimeInterval = 60
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func event(_ name: String, at minutes: Double) -> HookEvent {
        HookEvent(sessionID: "s1", kind: HookEvent.Kind(name: name), cwd: "/Users/me/code/shop-api", sentAt: start.addingTimeInterval(minutes * minute))
    }

    /// Applies the events to a store and records each change, as the app does.
    private func run(_ events: HookEvent...) -> ActivityStats {
        var store = SessionStore()
        var stats = ActivityStats()
        for event in events {
            let previous = store.sessions[event.sessionID]
            let current = store.apply(event)
            stats.record(previous: previous, current: current, at: event.sentAt, calendar: calendar)
        }
        return stats
    }

    @Test func countsATurnAndTheWaitInsideIt() {
        let stats = run(
            event("UserPromptSubmit", at: 0),
            event("PermissionRequest", at: 2),
            event("PostToolUse", at: 6),
            event("Stop", at: 10)
        )

        let day = stats.day(of: start, calendar: calendar)
        #expect(day.turns == 1)
        #expect(day.waits == 1)
        #expect(day.waitSeconds == 4 * minute)
        #expect(day.workSeconds == 6 * minute)
        #expect(day.longestWait == 4 * minute)
        #expect(day.longestWaitFolder == "shop-api")
        #expect(day.longestTurnFolder == "shop-api")
    }

    @Test func aFailedTurnCountsToo() {
        let stats = run(event("UserPromptSubmit", at: 0), event("StopFailure", at: 3))

        #expect(stats.day(of: start, calendar: calendar).turns == 1)
    }

    @Test func aRepeatedStopIsNotASecondTurn() {
        let stats = run(event("UserPromptSubmit", at: 0), event("Stop", at: 3), event("Stop", at: 4))

        #expect(stats.day(of: start, calendar: calendar).turns == 1)
    }

    @Test func keepsAMonth() {
        var stats = ActivityStats()
        var store = SessionStore()
        for day in 0..<40 {
            let base = Double(day) * 24 * 60
            for event in [event("UserPromptSubmit", at: base), event("Stop", at: base + 1)] {
                let previous = store.sessions["s1"]
                stats.record(previous: previous, current: store.apply(event), at: event.sentAt, calendar: calendar)
            }
        }
        stats.prune(now: start.addingTimeInterval(39 * 24 * 60 * minute), calendar: calendar)

        #expect(stats.days.count == ActivityStats.keptDays)
    }

    @Test func aWeekHasSevenDaysOldestFirstWithEmptyOnesFilledIn() throws {
        var monday = DayActivity()
        monday.turns = 3
        monday.workSeconds = 600
        monday.longestTurn = 400
        monday.longestTurnFolder = "api"
        var wednesday = DayActivity()
        wednesday.turns = 2
        wednesday.waits = 1
        wednesday.waitSeconds = 120
        wednesday.longestWait = 120
        wednesday.longestWaitFolder = "web"
        wednesday.longestTurn = 300
        wednesday.longestTurnFolder = "web"
        let stats = ActivityStats(days: ["2026-11-09": monday, "2026-11-11": wednesday, "2026-11-01": monday])
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 21)))

        let week = stats.days(endingAt: sunday, calendar: calendar)
        let total = stats.total(endingAt: sunday, calendar: calendar)

        #expect(week.map { ActivityStats.key(for: $0.day, calendar: calendar) } == [
            "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15",
        ])
        #expect(week.map(\.activity.turns) == [3, 0, 2, 0, 0, 0, 0])
        #expect(total.turns == 5)
        #expect(total.workSeconds == 600)
        #expect(total.waitSeconds == 120)
        #expect(total.longestTurn == 400)
        #expect(total.longestTurnFolder == "api")
        #expect(total.longestWaitFolder == "web")
    }
}
