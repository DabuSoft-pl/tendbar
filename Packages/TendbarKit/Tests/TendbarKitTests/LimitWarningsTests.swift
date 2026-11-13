import Foundation
import Testing
@testable import TendbarKit

@Suite struct LimitWarningsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func account(five: Double? = nil, week: Double? = nil, scoped: [ScopedWindow]? = nil) -> AccountUsage {
        AccountUsage(
            id: "|me@example.com",
            email: "me@example.com",
            fiveHour: five.map { LimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(3600)) },
            sevenDay: week.map { LimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(86400)) },
            scoped: scoped,
            updatedAt: now
        )
    }

    @Test func nothingBelowEighty() {
        #expect(LimitWarnings.pending(for: account(five: 79.9, week: 50), now: now, fired: []).isEmpty)
    }

    @Test func warnsOnceAtTheHighestThresholdReached() {
        let warnings = LimitWarnings.pending(for: account(five: 92, week: 81), now: now, fired: [])

        #expect(warnings.map(\.window) == [LimitWarnings.fiveHour, LimitWarnings.sevenDay])
        #expect(warnings.map(\.threshold) == [90, 80])
    }

    @Test func doesNotRepeatAndSkipsLowerThresholdsAfterAHigherOne() {
        let first = LimitWarnings.pending(for: account(five: 95), now: now, fired: [])
        let fired = Set(first.flatMap(LimitWarnings.keys(firing:)))

        #expect(LimitWarnings.pending(for: account(five: 95), now: now, fired: fired).isEmpty)
        #expect(LimitWarnings.pending(for: account(five: 85), now: now, fired: fired).isEmpty)
    }

    @Test func eightyThenNinetyWarnsTwice() {
        let eighty = LimitWarnings.pending(for: account(five: 82), now: now, fired: [])
        let fired = Set(eighty.flatMap(LimitWarnings.keys(firing:)))

        let ninety = LimitWarnings.pending(for: account(five: 91), now: now, fired: fired)

        #expect(eighty.map(\.threshold) == [80])
        #expect(ninety.map(\.threshold) == [90])
    }

    @Test func aNewWindowAfterResetWarnsAgain() {
        let fired = Set(LimitWarnings.pending(for: account(five: 85), now: now, fired: []).flatMap(LimitWarnings.keys(firing:)))
        var next = account(five: 85)
        next.fiveHour?.resetsAt = now.addingTimeInterval(5 * 3600 + 3600)

        #expect(LimitWarnings.pending(for: next, now: now, fired: fired).count == 1)
    }

    @Test func ignoresWindowsThatResetOrNeverStarted() {
        var reset = account(five: 99)
        reset.fiveHour?.resetsAt = now.addingTimeInterval(-1)
        let notStarted = account(scoped: [ScopedWindow(name: "Fable", window: LimitWindow(usedPercentage: 99, resetsAt: .distantFuture))])

        #expect(LimitWarnings.pending(for: reset, now: now, fired: []).isEmpty)
        #expect(LimitWarnings.pending(for: notStarted, now: now, fired: []).isEmpty)
    }

    @Test func coversModelScopedWindows() {
        let scoped = [ScopedWindow(name: "Fable", window: LimitWindow(usedPercentage: 88, resetsAt: now.addingTimeInterval(86400)))]

        #expect(LimitWarnings.pending(for: account(scoped: scoped), now: now, fired: []).map(\.window) == ["Fable"])
    }
}
