import Foundation
import Testing
import TendbarApplication
import TendbarDomain

@MainActor
@Suite struct UsageAndProfileUseCaseTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aReadingIsFiledUnderTheSignedInAccount() {
        let usage = InMemoryUsage()
        let emails = StubEmails()
        emails.emails["/Users/me/.claude-work"] = "work@example.com"
        let alerts = RecordingAlerts()
        let check = CheckLimitWarnings(usage: usage, fired: InMemoryFiredWarnings(), alerts: alerts, flasher: RecordingFlasher(), settings: StubSettings(), clock: FixedClock(date: now))
        let record = RecordUsageReading(repository: usage, output: usage, emails: emails, checkWarnings: check)

        record.execute(UsageReading(
            configDirectory: "/Users/me/.claude-work",
            fiveHour: LimitWindow(usedPercentage: 85, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: nil,
            readAt: now
        ))

        #expect(usage.store.current?.email == "work@example.com")
        #expect(usage.shown.count == 1)
        #expect(alerts.limits.map(\.threshold) == [80])
    }

    @Test func addingAProfileRemembersItsDirectoryOnce() throws {
        let profiles = InMemoryProfiles()
        let add = AddProfile(repository: profiles, directories: StubDirectories())

        try add.execute(name: "work")
        try add.execute(name: "work")

        #expect(profiles.directories == ["/Users/me/.claude-work"])
        #expect(throws: ProfileCreationError.invalidName) { try add.execute(name: "Not Valid") }
    }

    @Test func listsTheDefaultProfileFirstWithItsConnection() {
        let profiles = InMemoryProfiles()
        profiles.directories = ["/Users/me/.claude-work"]
        let connector = StubConnector()
        connector.statuses[nil] = .connected
        let emails = StubEmails()
        emails.emails[nil] = "me@example.com"

        let list = ListProfiles(repository: profiles, emails: emails, connector: connector).execute()

        #expect(list.map(\.directory) == [nil, "/Users/me/.claude-work"])
        #expect(list.map(\.connection) == [.connected, .disconnected])
        #expect(list.first?.email == "me@example.com")
        #expect(list.last?.launchCommand.hasSuffix("claude") == true)
    }

    @Test func withoutTheHelperThereIsNothingToConnect() throws {
        #expect(try CheckHookConnection(connector: nil).execute() == nil)
    }
}

@Suite struct HookAttentionTests {
    private func profile(_ directory: String?, _ connection: HookConnection?) -> ProfileSummary {
        ProfileSummary(directory: directory, email: nil, connection: connection)
    }

    @Test func connectedProfilesAndUnknownOnesNeedNothing() {
        let profiles = [profile(nil, .connected), profile("/a", nil)]

        #expect(HookAttention.profilesNeedingConnect(profiles).isEmpty)
        #expect(HookAttention.worst(of: profiles) == nil)
    }

    @Test func listsEveryProfileThatNeedsConnectInOrder() {
        let profiles = [profile(nil, .otherCopy), profile("/a", .connected), profile("/b", .disconnected)]

        #expect(HookAttention.profilesNeedingConnect(profiles).map(\.directory) == [nil, "/b"])
    }

    @Test func namesTheStateThatLosesTheMostEvents() {
        #expect(HookAttention.worst(of: [profile(nil, .outdated), profile("/a", .otherCopy)]) == .otherCopy)
        #expect(HookAttention.worst(of: [profile(nil, .otherCopy), profile("/a", .disconnected)]) == .disconnected)
        #expect(HookAttention.worst(of: [profile(nil, .disconnected), profile("/a", .helperGone)]) == .helperGone)
    }
}
