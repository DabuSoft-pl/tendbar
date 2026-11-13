import Foundation
import Testing
@testable import TendbarDomain

@Suite struct LimitPaceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 60 * 60

    @Test func evenPaceIsTheShareOfTheWindowThatHasPassed() throws {
        let window = LimitWindow(usedPercentage: 30, resetsAt: now.addingTimeInterval(4 * hour))

        let pace = try #require(window.evenPace(at: now, length: LimitWindow.fiveHourLength))
        #expect(abs(pace - 20) < 0.001)
    }

    @Test func noPaceAfterTheReset() {
        let window = LimitWindow(usedPercentage: 30, resetsAt: now.addingTimeInterval(-1))

        #expect(window.evenPace(at: now, length: LimitWindow.fiveHourLength) == nil)
        #expect(window.runsOut(readAt: now.addingTimeInterval(-hour), now: now, length: LimitWindow.fiveHourLength) == nil)
    }

    @Test func runsOutBeforeTheResetWhenUsageIsAhead() throws {
        // One hour into a five-hour window with 50% used: the other 50% lasts one more hour.
        let window = LimitWindow(usedPercentage: 50, resetsAt: now.addingTimeInterval(4 * hour))

        let date = try #require(window.runsOut(readAt: now, now: now, length: LimitWindow.fiveHourLength))
        #expect(abs(date.timeIntervalSince(now) - hour) < 1)
    }

    @Test func lastsWhenUsageIsBehind() {
        let window = LimitWindow(usedPercentage: 10, resetsAt: now.addingTimeInterval(4 * hour))

        #expect(window.runsOut(readAt: now, now: now, length: LimitWindow.fiveHourLength) == nil)
    }

    @Test func ignoresTheFirstMomentsOfAWindow() {
        let window = LimitWindow(usedPercentage: 4, resetsAt: now.addingTimeInterval(5 * hour - 60))

        #expect(window.runsOut(readAt: now, now: now, length: LimitWindow.fiveHourLength) == nil)
    }

    @Test func aProjectionInThePastIsDropped() {
        // Read three hours ago at a pace that ran out an hour after the reading.
        let readAt = now.addingTimeInterval(-3 * hour)
        let window = LimitWindow(usedPercentage: 50, resetsAt: readAt.addingTimeInterval(4 * hour))

        #expect(window.runsOut(readAt: readAt, now: now, length: LimitWindow.fiveHourLength) == nil)
    }
}
