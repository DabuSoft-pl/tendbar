import Foundation
import Testing
import TendbarApplication
import TendbarDomain

private struct StubProcesses: SessionProcessChecking {
    var running: [Int32: Bool]
    func isRunning(_ terminal: TerminalContext) -> Bool? { terminal.processID.flatMap { running[$0] } }
}

@MainActor
@Suite struct EndGoneSessionsTests {
    let sessions = InMemorySessions()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func apply(_ id: String, _ name: String, pid: Int32?) {
        sessions.store.apply(HookEvent(
            sessionID: id, kind: HookEvent.Kind(name: name), terminal: TerminalContext(processID: pid), sentAt: start
        ))
    }

    @Test func endsSessionsWhoseProcessIsGone() {
        apply("gone", "Stop", pid: 10)
        apply("alive", "UserPromptSubmit", pid: 11)
        apply("unknown", "Stop", pid: nil)
        apply("waiting", "PermissionRequest", pid: 12)

        EndGoneSessions(
            repository: sessions,
            output: sessions,
            processes: StubProcesses(running: [10: false, 11: true, 12: false]),
            clock: FixedClock(date: start.addingTimeInterval(60))
        ).execute()

        #expect(sessions.store.sessions["gone"]?.state == .ended)
        #expect(sessions.store.sessions["gone"]?.unread == false)
        #expect(sessions.store.sessions["alive"]?.state == .working)
        #expect(sessions.store.sessions["unknown"]?.state == .done)
        #expect(sessions.store.sessions["waiting"]?.state == .ended)
        #expect(sessions.store.sessions["waiting"]?.waitingSince == nil)
    }
}
