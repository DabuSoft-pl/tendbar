import Foundation
import Testing
@testable import TendbarDomain

@Suite struct SessionStoreTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        _ name: String,
        session: String = "s1",
        at offset: TimeInterval = 0,
        message: String? = nil,
        notificationType: String? = nil,
        terminal: TerminalContext = TerminalContext(program: "iTerm.app", tty: "/dev/ttys001")
    ) -> HookEvent {
        HookEvent(
            sessionID: session,
            kind: HookEvent.Kind(name: name),
            cwd: "/Users/me/code/app",
            transcriptPath: "/tmp/t.jsonl",
            message: message,
            notificationType: notificationType,
            terminal: terminal,
            sentAt: start.addingTimeInterval(offset)
        )
    }

    private func apply(_ store: inout SessionStore, _ events: HookEvent...) {
        for event in events { store.apply(event) }
    }

    @Test func followsATypicalTurn() {
        var store = SessionStore()

        apply(&store, event("SessionStart"))
        #expect(store.sessions["s1"]?.state == .idle)
        #expect(store.sessions["s1"]?.folderName == "app")

        apply(&store, event("UserPromptSubmit", at: 1))
        #expect(store.sessions["s1"]?.state == .working)

        apply(&store, event("Stop", at: 2))
        #expect(store.sessions["s1"]?.state == .done)
        #expect(store.sessions["s1"]?.unread == true)
    }

    @Test func permissionNeedsYouUntilTheToolRuns() {
        var store = SessionStore()
        apply(&store, event("UserPromptSubmit"))

        apply(&store, event("PermissionRequest", at: 1))
        apply(&store, event("Notification", at: 1, message: "Claude needs your permission to use Bash", notificationType: "permission_prompt"))
        #expect(store.sessions["s1"]?.state == .needsYou)
        #expect(store.sessions["s1"]?.message == "Claude needs your permission to use Bash")
        #expect(store.needsYouCount == 1)

        apply(&store, event("PostToolUse", at: 2))
        #expect(store.sessions["s1"]?.state == .working)
        #expect(store.sessions["s1"]?.message == nil)
        #expect(store.needsYouCount == 0)
    }

    @Test func postToolUseDoesNotReviveAFinishedTurn() {
        var store = SessionStore()
        apply(&store, event("Stop"), event("PostToolUse", at: 1))

        #expect(store.sessions["s1"]?.state == .done)
    }

    @Test func idlePromptKeepsDoneState() {
        var store = SessionStore()
        apply(&store, event("Stop"), event("Notification", at: 60, message: "Claude is waiting for your input", notificationType: "idle_prompt"))

        #expect(store.sessions["s1"]?.state == .done)
        #expect(store.sessions["s1"]?.message == nil)
    }

    @Test func failureAndEnd() {
        var store = SessionStore()
        apply(&store, event("UserPromptSubmit"), event("StopFailure", at: 1, message: "API Error: 529"))
        #expect(store.sessions["s1"]?.state == .failed)
        #expect(store.sessions["s1"]?.message == "API Error: 529")

        apply(&store, event("SessionEnd", at: 2))
        #expect(store.sessions["s1"]?.state == .ended)
        #expect(store.sessions["s1"]?.unread == false)

        apply(&store, event("SessionStart", at: 3))
        #expect(store.sessions["s1"]?.state == .idle)
    }

    @Test func newPromptClearsUnread() {
        var store = SessionStore()
        apply(&store, event("Stop"), event("UserPromptSubmit", at: 1))

        #expect(store.sessions["s1"]?.unread == false)
    }

    @Test func ordersNewestFirstAndKeepsLatestTerminal() {
        var store = SessionStore()
        apply(&store, event("SessionStart", session: "a"), event("SessionStart", session: "b", at: 5))
        apply(&store, event("Stop", session: "a", at: 10, terminal: TerminalContext(program: "Apple_Terminal", tty: "/dev/ttys009")))

        #expect(store.ordered.map(\.id) == ["a", "b"])
        #expect(store.sessions["a"]?.terminal.tty == "/dev/ttys009")
    }

    @Test func markSeenAndRemoveEnded() {
        var store = SessionStore()
        apply(&store, event("Stop", session: "a"), event("SessionEnd", session: "b"))

        store.markSeen("a")
        store.removeEnded()

        #expect(store.sessions["a"]?.unread == false)
        #expect(store.sessions["b"] == nil)
    }

    @Test func pruneDropsOldSessions() {
        var store = SessionStore()
        apply(&store, event("SessionEnd", session: "ended"), event("Stop", session: "stale"), event("Stop", session: "fresh", at: 6 * 24 * 3600))

        store.prune(now: start.addingTimeInterval(7 * 24 * 3600 + 1))

        #expect(Set(store.sessions.keys) == ["fresh"])
    }
}
