import Foundation
import Testing
import TendbarDomain
@testable import TendbarInfrastructure

@MainActor
@Suite struct JSONRepositoryTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tendbar-\(UUID().uuidString)")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func sessionsSurviveARestart() throws {
        let url = directory.appendingPathComponent("sessions.json")
        var store = SessionStore()
        store.apply(HookEvent(sessionID: "s1", kind: .stop, cwd: "/Users/me/app", terminal: TerminalContext(program: "iTerm.app"), sentAt: now))
        store.setPreview("Done: tests pass", for: "s1")

        JSONSessionRepository(url: url).save(store)

        #expect(JSONSessionRepository(url: url).load() == store)
        #expect(JSONSessionRepository(url: url.appendingPathExtension("missing")).load() == SessionStore())
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func readsTheFileFormatOfEarlierVersions() throws {
        let url = directory.appendingPathComponent("sessions.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"sessions":{"s1":{"id":"s1","cwd":"/Users/me/app","state":"needsYou","terminal":{"program":"iTerm.app"},"startedAt":"2027-01-15T08:00:00Z","updatedAt":"2027-01-15T08:01:00Z","unread":true,"message":"Allow Bash?"}}}"#.utf8).write(to: url)

        let session = try #require(JSONSessionRepository(url: url).load().sessions["s1"])

        #expect(session.state == .needsYou)
        #expect(session.folderName == "app")
        #expect(session.terminal.program == "iTerm.app")
        #expect(session.message == "Allow Bash?")
    }

    @Test func usageSurvivesARestart() {
        let url = directory.appendingPathComponent("usage.json")
        let store = UsageStore(accounts: [AccountUsage(
            id: "|me@example.com",
            email: "me@example.com",
            fiveHour: LimitWindow(usedPercentage: 42, resetsAt: now.addingTimeInterval(3600)),
            updatedAt: now
        )])

        JSONUsageRepository(url: url).save(store)

        #expect(JSONUsageRepository(url: url).load() == store)
    }
}
