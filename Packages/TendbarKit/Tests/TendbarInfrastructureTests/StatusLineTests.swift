import Foundation
import Testing
import TendbarDomain
@testable import TendbarInfrastructure

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
        #expect(try installer.status() == .helperGone)

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

@MainActor
@Suite struct StatusLineReadingTests {
    private func envelope(_ raw: String, configDirectory: String? = nil, channel: String? = HookEnvelope.statusLineChannel) -> HookEnvelope {
        HookEnvelope(
            sentAt: Date(timeIntervalSince1970: 1_800_000_000),
            terminal: TerminalContext(configDirectory: configDirectory),
            raw: raw,
            channel: channel
        )
    }

    @Test func turnsRateLimitsIntoAReading() {
        let raw = #"{"session_id":"s1","rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800003600},"seven_day":{"used_percentage":41,"resets_at":1800300000}}}"#

        #expect(envelope(raw, configDirectory: "/Users/me/.claude-work").message() == .usage(UsageReading(
            configDirectory: "/Users/me/.claude-work",
            fiveHour: LimitWindow(usedPercentage: 23.5, resetsAt: Date(timeIntervalSince1970: 1_800_003_600)),
            sevenDay: LimitWindow(usedPercentage: 41, resetsAt: Date(timeIntervalSince1970: 1_800_300_000)),
            readAt: Date(timeIntervalSince1970: 1_800_000_000)
        )))
    }

    @Test func ignoresInputWithoutLimits() {
        #expect(envelope(#"{"session_id":"s1","model":{"id":"x"}}"#).message() == nil)
    }

    @Test func rateLimitsInAHookAreNotAReading() {
        let message = envelope(#"{"session_id":"s1","hook_event_name":"Stop","rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1}}}"#, channel: nil).message()

        guard case let .hook(event) = message else {
            Issue.record("expected a hook event")
            return
        }
        #expect(event.kind == .stop)
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
}
