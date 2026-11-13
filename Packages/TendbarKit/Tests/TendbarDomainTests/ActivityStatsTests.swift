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
}
