import Foundation
import Testing
@testable import TendbarDomain

@Suite struct LimitWarningsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func account(five: Double? = nil, week: Double? = nil) -> AccountUsage {
        AccountUsage(
            id: "|me@example.com",
            email: "me@example.com",
            fiveHour: five.map { LimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(3600)) },
            sevenDay: week.map { LimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(86400)) },
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

    @Test func ignoresWindowsThatAlreadyReset() {
        var reset = account(five: 99)
        reset.fiveHour?.resetsAt = now.addingTimeInterval(-1)

        #expect(LimitWarnings.pending(for: reset, now: now, fired: []).isEmpty)
    }
}

@Suite struct LimitResetTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func account(resetsAt: Date) -> AccountUsage {
        AccountUsage(id: "a", fiveHour: LimitWindow(usedPercentage: 85, resetsAt: resetsAt), updatedAt: now.addingTimeInterval(-3600))
    }

    @Test func aWarnedWindowAnnouncesItsReset() {
        let resetsAt = now.addingTimeInterval(-60)
        let fired: Set<String> = [LimitWarnings.key(accountID: "a", window: LimitWarnings.fiveHour, resetsAt: resetsAt, threshold: 80)]

        let resets = LimitWarnings.resets(for: account(resetsAt: resetsAt), now: now, fired: fired)

        #expect(resets == [LimitReset(accountID: "a", window: LimitWarnings.fiveHour, resetsAt: resetsAt)])
    }

    @Test func onlyOnceAndOnlyAfterAWarning() {
        let resetsAt = now.addingTimeInterval(-60)
        let warned = LimitWarnings.key(accountID: "a", window: LimitWarnings.fiveHour, resetsAt: resetsAt, threshold: 80)
        let announced = LimitWarnings.resetKey(accountID: "a", window: LimitWarnings.fiveHour, resetsAt: resetsAt)

        #expect(LimitWarnings.resets(for: account(resetsAt: resetsAt), now: now, fired: []).isEmpty)
        #expect(LimitWarnings.resets(for: account(resetsAt: resetsAt), now: now, fired: [warned, announced]).isEmpty)
        #expect(LimitWarnings.resets(for: account(resetsAt: now.addingTimeInterval(60)), now: now, fired: [warned]).isEmpty)
    }
}
