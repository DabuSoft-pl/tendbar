import Foundation
import Testing
@testable import TendbarDomain

@Suite struct UsageStoreTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(five: Double? = nil, week: Double? = nil, configDirectory: String? = nil, at offset: TimeInterval = 0) -> UsageReading {
        UsageReading(
            configDirectory: configDirectory,
            fiveHour: five.map { LimitWindow(usedPercentage: $0, resetsAt: Date(timeIntervalSince1970: 1_800_003_600)) },
            sevenDay: week.map { LimitWindow(usedPercentage: $0, resetsAt: Date(timeIntervalSince1970: 1_800_300_000)) },
            readAt: now.addingTimeInterval(offset)
        )
    }

    @Test func recordsBothWindows() throws {
        var store = UsageStore()

        let recorded = store.record(reading(five: 23.5, week: 41), email: nil)

        #expect(recorded)

        let account = try #require(store.accounts[""])
        #expect(account.fiveHour == LimitWindow(usedPercentage: 23.5, resetsAt: Date(timeIntervalSince1970: 1_800_003_600)))
        #expect(account.sevenDay?.usedPercentage == 41)
        #expect(account.configDirectory == nil)
    }

    @Test func keysAccountsByConfigDirectory() {
        var store = UsageStore()

        store.record(reading(five: 10), email: nil)
        store.record(reading(five: 10, configDirectory: "/Users/me/.claude-work"), email: nil)

        #expect(store.ordered.map(\.id) == ["", "/Users/me/.claude-work"])
    }

    @Test func keepsAccountsSwitchedInTheSameDirectoryApart() {
        var store = UsageStore()

        store.record(reading(five: 80), email: "Work@Example.com")
        store.record(reading(five: 5), email: "me@example.com")

        #expect(store.ordered.map(\.email) == ["me@example.com", "Work@Example.com"])
        #expect(store.accounts["|work@example.com"]?.fiveHour?.usedPercentage == 80)
        #expect(store.accounts["|me@example.com"]?.fiveHour?.usedPercentage == 5)

        store.remove("|me@example.com")
        #expect(store.accounts.count == 1)
    }

    @Test func theAccountReadLastIsCurrent() {
        var store = UsageStore()
        store.record(reading(five: 87, at: 0), email: "old@example.com")
        store.record(reading(five: 12, week: 40, at: 60), email: "new@example.com")

        #expect(store.current?.email == "new@example.com")
        #expect(store.currentFirst.map(\.email) == ["new@example.com", "old@example.com"])
        #expect(store.currentLimit(at: now) == 40)
    }

    @Test func treatsTheDefaultDirectoryAsTheDefaultAccount() {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        #expect(UsageStore.accountKey(configDirectory: home) == "")
        #expect(UsageStore.accountKey(configDirectory: home + "/") == "")
        #expect(UsageStore.accountKey(configDirectory: nil) == "")
    }

    @Test func aMissingWindowMeansItWasReset() {
        var store = UsageStore()
        store.record(reading(five: 90, week: 50), email: nil)

        store.record(reading(week: 51, at: 1), email: nil)

        #expect(store.accounts[""]?.fiveHour == nil)
        #expect(store.accounts[""]?.sevenDay?.usedPercentage == 51)
    }

    @Test func anOlderReadingDoesNotOverwriteANewerOne() {
        var store = UsageStore()
        store.record(reading(five: 50, at: 10), email: nil)

        let recorded = store.record(reading(five: 20, at: 0), email: nil)

        #expect(!recorded)
        #expect(store.accounts[""]?.fiveHour?.usedPercentage == 50)
    }

    @Test func percentageDropsToZeroAfterReset() {
        let window = LimitWindow(usedPercentage: 80, resetsAt: Date(timeIntervalSince1970: 100))

        #expect(window.percentage(at: Date(timeIntervalSince1970: 99)) == 80)
        #expect(window.percentage(at: Date(timeIntervalSince1970: 100)) == 0)
    }
}
