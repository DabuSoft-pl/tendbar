import Foundation
import Testing
import TendbarApplication
import TendbarDomain

@MainActor
@Suite struct SessionUseCaseTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String, state: SessionState, unread: Bool = false, age: TimeInterval = 0) -> Session {
        Session(id: id, terminal: TerminalContext(program: "iTerm.app", tty: "/dev/ttys00\(id.count)"), state: state, startedAt: now, updatedAt: now.addingTimeInterval(-age), unread: unread)
    }

    @Test func openingASessionMarksItReadAndJumps() {
        let sessions = InMemorySessions([session("s1", state: .done, unread: true)])
        let alerts = RecordingAlerts()
        let navigator = StubNavigator()
        navigator.outcome = .notRunning

        let outcome = OpenSession(repository: sessions, output: sessions, alerts: alerts, navigator: navigator).execute(sessionID: "s1")

        #expect(outcome == .notRunning)
        #expect(sessions.store.sessions["s1"]?.unread == false)
        #expect(alerts.dismissed == ["s1"])
        #expect(navigator.jumps.map(\.program) == ["iTerm.app"])
    }

    @Test func openingAnUnknownSessionDoesNothing() {
        let navigator = StubNavigator()
        let sessions = InMemorySessions()

        #expect(OpenSession(repository: sessions, output: sessions, alerts: RecordingAlerts(), navigator: navigator).execute(sessionID: "gone") == nil)
        #expect(navigator.jumps.isEmpty)
    }

    @Test func theShortcutOpensTheSessionThatNeedsYou() {
        let sessions = InMemorySessions([session("s1", state: .done, unread: true), session("s22", state: .needsYou, unread: true, age: 60)])
        let navigator = StubNavigator()
        navigator.outcome = .jumped
        let open = OpenSession(repository: sessions, output: sessions, alerts: RecordingAlerts(), navigator: navigator)

        #expect(OpenNextSession(repository: sessions, openSession: open).execute() == .jumped)
        #expect(sessions.store.sessions["s22"]?.unread == false)
        #expect(sessions.store.sessions["s1"]?.unread == true)
    }

    @Test func theShortcutDoesNothingWhenNothingNeedsYou() {
        let sessions = InMemorySessions([session("s1", state: .working)])
        let navigator = StubNavigator()
        let open = OpenSession(repository: sessions, output: sessions, alerts: RecordingAlerts(), navigator: navigator)

        #expect(OpenNextSession(repository: sessions, openSession: open).execute() == nil)
        #expect(navigator.jumps.isEmpty)
    }

    @Test func startingDropsStaleSessions() {
        let sessions = InMemorySessions([session("fresh", state: .done), session("old", state: .done, age: 8 * 24 * 3600)])

        StartSessions(repository: sessions, output: sessions, clock: FixedClock(date: now)).execute()

        #expect(Set(sessions.store.sessions.keys) == ["fresh"])
        #expect(sessions.shown.count == 1)
    }

    @Test func markAllSeenClearsEveryUnreadBanner() {
        let sessions = InMemorySessions([session("a", state: .done, unread: true), session("b", state: .working)])
        let alerts = RecordingAlerts()

        MarkAllSessionsSeen(repository: sessions, output: sessions, alerts: alerts).execute()

        #expect(alerts.dismissed == ["a"])
        #expect(!sessions.store.hasUnread)
    }
}
