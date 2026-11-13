import Foundation
import Testing
@testable import TendbarKit

@Suite struct StatusLineInstallerTests {
    let settings: URL
    let hookPath = "/Applications/Tendbar.app/Contents/MacOS/tendbar-hook"
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tendbar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settings = directory.appendingPathComponent("settings.json")
    }

    private func write(_ json: String) throws {
        try Data(json.utf8).write(to: settings)
    }

    private func statusLine() throws -> [String: Any]? {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        return object["statusLine"] as? [String: Any]
    }

    @Test func wrapsAnExistingStatusLineAndRestoresIt() throws {
        let original = #"'/Applications/Other.app/Contents/MacOS/Other' --relay --data-dir '/Users/me/Library/Application Support/Other'"#
        let json = try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": original, "padding": 2]])
        try json.write(to: settings)
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)

        try installer.connect(now: now)
        let wrapped = try #require(try statusLine())
        let command = try #require(wrapped["command"] as? String)
        #expect(command.hasPrefix("'\(hookPath)' --statusline --next "))
        #expect(HookInstaller.wrappedCommand(in: command) == original)
        #expect(wrapped["padding"] as? Int == 2)
        #expect(try installer.status() == .connected)

        try installer.disconnect(now: now.addingTimeInterval(1))
        let restored = try #require(try statusLine())
        #expect(restored["command"] as? String == original)
        #expect(restored["padding"] as? Int == 2)
    }

    @Test func addsAStatusLineWhenThereIsNoneAndRemovesItAgain() throws {
        try write("{}")
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)

        try installer.connect(now: now)
        #expect(try statusLine()?["command"] as? String == "'\(hookPath)' --statusline")

        try installer.disconnect(now: now.addingTimeInterval(1))
        #expect(try statusLine() == nil)
    }

    @Test func reconnectingKeepsTheOriginalCommandOnce() throws {
        try write(#"{"statusLine":{"type":"command","command":"~/.claude/statusline.sh"}}"#)
        try HookInstaller(settingsURL: settings, hookPath: "/old/tendbar-hook").connect(now: now)
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)
        #expect(try installer.status() == .outdated)

        try installer.connect(now: now.addingTimeInterval(1))

        let command = try #require(try statusLine()?["command"] as? String)
        #expect(command.hasPrefix("'\(hookPath)' --statusline --next "))
        #expect(HookInstaller.wrappedCommand(in: command) == "~/.claude/statusline.sh")
    }

    @Test func hooksWithoutStatusLineAreOutdated() throws {
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)
        try installer.connect(now: now)
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        object["statusLine"] = nil
        try JSONSerialization.data(withJSONObject: object).write(to: settings)

        #expect(try installer.status() == .outdated)
    }
}

@Suite struct UsageStoreTests {
    private func envelope(_ raw: String, configDirectory: String? = nil, channel: String? = HookEnvelope.statusLineChannel) -> HookEnvelope {
        HookEnvelope(
            sentAt: Date(timeIntervalSince1970: 1_800_000_000),
            terminal: TerminalContext(configDirectory: configDirectory),
            raw: raw,
            channel: channel
        )
    }

    @Test func readsBothWindows() throws {
        var store = UsageStore()
        let raw = #"{"session_id":"s1","rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800003600},"seven_day":{"used_percentage":41,"resets_at":1800300000}}}"#

        let applied = store.apply(envelope(raw))

        #expect(applied)
        let account = try #require(store.accounts[""])
        #expect(account.fiveHour == LimitWindow(usedPercentage: 23.5, resetsAt: Date(timeIntervalSince1970: 1_800_003_600)))
        #expect(account.sevenDay?.usedPercentage == 41)
        #expect(account.configDirectory == nil)
    }

    @Test func keysAccountsByConfigDirectory() {
        var store = UsageStore()
        let raw = #"{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":1800003600}}}"#

        store.apply(envelope(raw))
        store.apply(envelope(raw, configDirectory: "/Users/me/.claude-work"))

        #expect(store.ordered.map(\.id) == ["", "/Users/me/.claude-work"])
    }

    @Test func keepsAccountsSwitchedInTheSameDirectoryApart() throws {
        var store = UsageStore()
        let first = #"{"rate_limits":{"five_hour":{"used_percentage":80,"resets_at":1800003600}}}"#
        let second = #"{"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":1800003600}}}"#

        store.apply(envelope(first), email: "Work@Example.com")
        store.apply(envelope(second), email: "me@example.com")

        #expect(store.ordered.map(\.email) == ["me@example.com", "Work@Example.com"])
        #expect(store.accounts["|work@example.com"]?.fiveHour?.usedPercentage == 80)
        #expect(store.accounts["|me@example.com"]?.fiveHour?.usedPercentage == 5)

        store.remove("|me@example.com")
        #expect(store.accounts.count == 1)
    }

    @Test func readsTheLoggedInEmailAndCachesIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tendbar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(".claude.json")
        try Data(#"{"oauthAccount":{"emailAddress":"a@example.com","accountUuid":"x"},"projects":{}}"#.utf8).write(to: file)
        let cache = AccountEmailCache()

        #expect(cache.email(configDirectory: directory.path) == "a@example.com")

        try Data(#"{"oauthAccount":{"emailAddress":"b@example.com"}}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: file.path)
        #expect(cache.email(configDirectory: directory.path) == "b@example.com")
        #expect(cache.email(configDirectory: directory.appendingPathComponent("missing").path) == nil)
    }

    @Test func treatsTheDefaultDirectoryAsTheDefaultAccount() {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        #expect(UsageStore.accountKey(configDirectory: home) == "")
        #expect(UsageStore.accountKey(configDirectory: home + "/") == "")
        #expect(UsageStore.accountKey(configDirectory: nil) == "")
    }

    @Test func ignoresInputWithoutLimitsAndHookEvents() {
        var store = UsageStore()

        let withoutLimits = store.apply(envelope(#"{"session_id":"s1","model":{"id":"x"}}"#))
        let fromHook = store.apply(envelope(#"{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1}}}"#, channel: nil))

        #expect(!withoutLimits)
        #expect(!fromHook)
        #expect(store.accounts.isEmpty)
    }

    @Test func aMissingWindowMeansItWasReset() {
        var store = UsageStore()
        store.apply(envelope(#"{"rate_limits":{"five_hour":{"used_percentage":90,"resets_at":1800003600},"seven_day":{"used_percentage":50,"resets_at":1800300000}}}"#))

        store.apply(envelope(#"{"rate_limits":{"seven_day":{"used_percentage":51,"resets_at":1800300000}}}"#))

        #expect(store.accounts[""]?.fiveHour == nil)
        #expect(store.accounts[""]?.sevenDay?.usedPercentage == 51)
    }

    @Test func percentageDropsToZeroAfterReset() {
        let window = LimitWindow(usedPercentage: 80, resetsAt: Date(timeIntervalSince1970: 100))

        #expect(window.percentage(at: Date(timeIntervalSince1970: 99)) == 80)
        #expect(window.percentage(at: Date(timeIntervalSince1970: 100)) == 0)
    }
}
