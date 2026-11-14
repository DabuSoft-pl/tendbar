import Foundation
import Testing
import TendbarDomain
@testable import TendbarInfrastructure

@Suite struct HookInstallerTests {
    let directory: URL
    let settings: URL
    let hookPath = "/Applications/Tendbar.app/Contents/MacOS/tendbar-hook"
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("tendbar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settings = directory.appendingPathComponent("settings.json")
    }

    private func write(_ json: String) throws {
        try Data(json.utf8).write(to: settings)
    }

    private func read() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    }

    private func commands(_ event: String, in object: [String: Any]) -> [String] {
        let groups = (object["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    private func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains("tendbar-backup") }
    }

    @Test func connectsWhenSettingsAreMissing() throws {
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)

        let backup = try installer.connect(now: now)

        #expect(backup == nil)
        #expect(try installer.status() == .connected)
        for event in HookInstaller.events {
            #expect(commands(event, in: try read()) == ["'\(hookPath)'"])
        }
    }

    @Test func keepsForeignHooksAndOtherSettings() throws {
        try write("""
        {"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/local/bin/other"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/bin/guard"}]}]}}
        """)
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)

        try installer.connect(now: now)
        let object = try read()

        #expect(object["theme"] as? String == "dark")
        #expect(commands("Stop", in: object) == ["/usr/local/bin/other", "'\(hookPath)'"])
        #expect(commands("PreToolUse", in: object) == ["/bin/guard"])
    }

    @Test func connectingTwiceDoesNotDuplicate() throws {
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)

        try installer.connect(now: now)
        try installer.connect(now: now.addingTimeInterval(1))

        #expect(commands("Stop", in: try read()) == ["'\(hookPath)'"])
    }

    @Test func reconnectReplacesAnOldPath() throws {
        let old = "/old/Tendbar.app/Contents/MacOS/tendbar-hook"
        try HookInstaller(settingsURL: settings, hookPath: old).connect(now: now)
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath, fileExists: { _ in true })
        #expect(try installer.status() == .otherCopy)

        try installer.connect(now: now.addingTimeInterval(1))

        #expect(try installer.status() == .connected)
        #expect(commands("Stop", in: try read()) == ["'\(hookPath)'"])
    }

    @Test func disconnectRemovesOnlyOurHooks() throws {
        try write(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/local/bin/other"}]}]}}"#)
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)
        try installer.connect(now: now)

        try installer.disconnect(now: now.addingTimeInterval(1))
        let object = try read()

        #expect(try installer.status() == .disconnected)
        #expect(commands("Stop", in: object) == ["/usr/local/bin/other"])
        #expect((object["hooks"] as? [String: Any])?["SessionStart"] == nil)
    }

    @Test func disconnectDropsEmptyHooksObject() throws {
        try write(#"{"theme":"dark"}"#)
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)
        try installer.connect(now: now)

        try installer.disconnect(now: now.addingTimeInterval(1))

        #expect(try read()["hooks"] == nil)
    }

    @Test func backsUpBeforeEveryChangeAndKeepsFive() throws {
        try write(#"{"theme":"dark"}"#)
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)

        let first = try installer.connect(now: now)
        #expect(try String(contentsOf: first!, encoding: .utf8) == #"{"theme":"dark"}"#)
        for second in 1...7 {
            try installer.connect(now: now.addingTimeInterval(TimeInterval(second)))
        }

        #expect(try backups().count == HookInstaller.backupLimit)
    }

    @Test func keepsFilePermissions() throws {
        try write("{}")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)

        try HookInstaller(settingsURL: settings, hookPath: hookPath).connect(now: now)

        let mode = try FileManager.default.attributesOfItem(atPath: settings.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func writesThroughSymlink() throws {
        let real = directory.appendingPathComponent("dotfiles-settings.json")
        try Data("{}".utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: real)

        try HookInstaller(settingsURL: settings, hookPath: hookPath).connect(now: now)

        let type = try FileManager.default.attributesOfItem(atPath: settings.path)[.type] as? FileAttributeType
        #expect(type == .typeSymbolicLink)
        #expect(commands("Stop", in: try JSONSerialization.jsonObject(with: Data(contentsOf: real)) as! [String: Any]).count == 1)
    }

    @Test func refusesUnexpectedFormat() throws {
        try write(#"{"hooks":{"Stop":"oops"}}"#)
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)

        #expect(throws: HookInstallerError.unexpectedHooksFormat("Stop")) { try installer.connect(now: now) }
        #expect(try String(contentsOf: settings, encoding: .utf8) == #"{"hooks":{"Stop":"oops"}}"#)
    }

    @Test func refusesInvalidJSONWithoutTouchingIt() throws {
        try write("{ not json")
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)

        #expect(throws: (any Error).self) { try installer.connect(now: now) }
        #expect(try String(contentsOf: settings, encoding: .utf8) == "{ not json")
        #expect(try backups().isEmpty)
    }

    @Test func quotesPathsWithSpacesAndQuotes() {
        #expect(HookInstaller.command(for: "/Users/me/My Apps/Tendbar.app/x") == "'/Users/me/My Apps/Tendbar.app/x'")
        #expect(HookInstaller.command(for: "/a'b") == #"'/a'\''b'"#)
    }

    @Test func permissionHooksWaitLongerThanTheOthers() throws {
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)
        try installer.connect(now: now)

        let timeouts = HookInstaller.ourTimeouts(in: try read())

        #expect(timeouts["PermissionRequest"] == [HookInstaller.permissionTimeoutSeconds])
        #expect(timeouts["Stop"] == [HookInstaller.timeoutSeconds])
        #expect(HookInstaller.permissionWaitSeconds < Double(HookInstaller.permissionTimeoutSeconds))
    }

    @Test func anOldTimeoutCountsAsOutdated() throws {
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath)
        try installer.connect(now: now)
        var object = try read()
        var hooks = object["hooks"] as! [String: Any]
        hooks["PermissionRequest"] = [["hooks": [["type": "command", "command": "'\(hookPath)'", "timeout": 3]]]]
        object["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: object).write(to: settings)

        #expect(try installer.status() == .outdated)
    }

    @Test func hooksOfAnotherCopyThatIsGoneStopEveryEvent() throws {
        let gone = "/Users/me/build/release/Tendbar.app/Contents/MacOS/tendbar-hook"
        try HookInstaller(settingsURL: settings, hookPath: gone).connect(now: now)
        let installer = HookInstaller(settingsURL: settings, hookPath: hookPath, fileExists: { $0 != gone })

        #expect(try installer.status() == .helperGone)
    }

    @Test func readsTheHelperPathBackFromAQuotedCommand() {
        let path = "/Users/o'brien/Tendbar.app/Contents/MacOS/tendbar-hook"

        #expect(HookInstaller.helperPath(in: HookInstaller.command(for: path)) == path)
        #expect(HookInstaller.helperPath(in: HookInstaller.statusLineCommand(hookPath: path, next: "x")) == path)
        #expect(HookInstaller.helperPath(in: "/usr/local/bin/tendbar-hook --statusline") == "/usr/local/bin/tendbar-hook")
    }
}
