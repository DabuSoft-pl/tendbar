import Foundation
import Testing
@testable import TendbarKit

@Suite struct ClaudeSwapUsageTests {
    private func file(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tendbar-swap-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        return url
    }

    let sample = """
    {"schemaVersion":2,"accounts":{
      "1":{"email":"work@example.com","organizationUuid":"o1","consecutiveFailures":0,
           "lastGood":{"five_hour":{"pct":37.0,"resets_at":"2026-11-13T10:30:00.104137+00:00","countdown":"3h","clock":"11:30"},
                       "seven_day":{"pct":47.0,"resets_at":"2026-11-18T08:00:00+00:00","countdown":"5d","clock":"Wed"},
                       "scoped":[{"name":"Fable","pct":12.0,"resets_at":"2026-11-18T08:00:00+00:00","countdown":"5d","clock":"Wed"}]},
           "fetchedAt":1794551664.264},
      "2":{"email":"me@example.com","lastGood":{"five_hour":{"pct":0.0,"resets_at":null},"seven_day":{"pct":3.0,"resets_at":"2026-11-19T08:00:00Z"}},"fetchedAt":1794551000},
      "3":{"email":"broken@example.com","lastGood":null,"fetchedAt":null}
    }}
    """

    @Test func readsEveryAccountWithAGoodReading() throws {
        let accounts = ClaudeSwapUsage.read(from: try file(sample))

        #expect(accounts.map(\.email) == ["me@example.com", "work@example.com"])
        let work = try #require(accounts.last)
        #expect(work.id == "|work@example.com")
        #expect(work.fiveHour?.usedPercentage == 37)
        #expect(work.fiveHour?.resetsAt == ClaudeSwapUsage.date(from: "2026-11-13T10:30:00.104137+00:00"))
        #expect(work.scoped?.first?.name == "Fable")
        #expect(work.scoped?.first?.window.usedPercentage == 12)
        #expect(work.updatedAt == Date(timeIntervalSince1970: 1_794_551_664.264))
        #expect(work.source == .claudeSwap)
    }

    @Test func aWindowWithoutResetIsNotStarted() throws {
        let me = try #require(ClaudeSwapUsage.read(from: try file(sample)).first)

        #expect(me.fiveHour == LimitWindow(usedPercentage: 0, resetsAt: .distantFuture))
        #expect(me.sevenDay?.resetsAt == ClaudeSwapUsage.date(from: "2026-11-19T08:00:00Z"))
    }

    @Test func unreadableFilesGiveNothing() throws {
        #expect(ClaudeSwapUsage.read(from: try file("{ nope")).isEmpty)
        #expect(ClaudeSwapUsage.read(from: try file(#"{"accounts":[]}"#)).isEmpty)
        #expect(ClaudeSwapUsage.read(from: URL(fileURLWithPath: "/nonexistent/usage.json")).isEmpty)
    }

    @Test func newestReadingWinsAndScopedWindowsSurvive() throws {
        var store = UsageStore()
        let swap = try #require(ClaudeSwapUsage.read(from: try file(sample)).last)
        store.merge(swap)

        let older = HookEnvelope(
            sentAt: swap.updatedAt.addingTimeInterval(-60),
            terminal: TerminalContext(),
            raw: #"{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":1800003600}}}"#,
            channel: HookEnvelope.statusLineChannel
        )
        store.apply(older, email: "work@example.com")
        #expect(store.accounts["|work@example.com"]?.fiveHour?.usedPercentage == 37)

        var newer = older
        newer.sentAt = swap.updatedAt.addingTimeInterval(60)
        store.apply(newer, email: "work@example.com")
        let merged = try #require(store.accounts["|work@example.com"])
        #expect(merged.fiveHour?.usedPercentage == 10)
        #expect(merged.source == .statusLine)
        #expect(merged.scoped?.first?.name == "Fable")
    }
}
