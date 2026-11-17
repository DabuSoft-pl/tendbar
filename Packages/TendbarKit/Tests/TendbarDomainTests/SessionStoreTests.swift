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
        for event in events { store.applySettled(event) }
    }

    @Test func remembersWhenTheTurnStarted() {
        var store = SessionStore()

        apply(&store, event("SessionStart"), event("UserPromptSubmit", at: 5), event("PostToolUse", at: 30))
        #expect(store.sessions["s1"]?.turnStartedAt == start.addingTimeInterval(5))

        apply(&store, event("Stop", at: 60), event("UserPromptSubmit", at: 90))
        #expect(store.sessions["s1"]?.turnStartedAt == start.addingTimeInterval(90))
    }

    @Test func aStopIsDoneOnlyOnceTheGracePassed() {
        var store = SessionStore()
        store.apply(event("UserPromptSubmit"))
        store.apply(event("Stop", at: 10))

        #expect(store.finishPendingStops(now: start.addingTimeInterval(12)).isEmpty)
        #expect(store.sessions["s1"]?.state == .working)
        #expect(store.finishPendingStops(now: start.addingTimeInterval(13)).count == 1)
        #expect(store.sessions["s1"]?.state == .done)
        #expect(store.sessions["s1"]?.stopDeferred == false)
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

    @Test func nextForYouPrefersTheLongestWaitThenFailuresThenUnreadReplies() {
        func session(_ id: String, _ state: SessionState, unread: Bool = false, at offset: TimeInterval, waiting: TimeInterval? = nil) -> Session {
            Session(
                id: id, state: state, startedAt: start, updatedAt: start.addingTimeInterval(offset),
                waitingSince: waiting.map { start.addingTimeInterval($0) }, unread: unread
            )
        }
        var store = SessionStore(sessions: [
            session("done", .done, unread: true, at: 1),
            session("failed", .failed, unread: true, at: 2),
            session("read", .done, at: 0),
            session("working", .working, at: 0),
            session("newer-wait", .needsYou, unread: true, at: 9, waiting: 9),
            session("older-wait", .needsYou, unread: true, at: 10, waiting: 3),
        ])

        #expect(store.nextForYou?.id == "older-wait")
        store = SessionStore(sessions: store.sessions.values.filter { $0.state != .needsYou })
        #expect(store.nextForYou?.id == "failed")
        store.markSeen("failed")
        #expect(store.nextForYou?.id == "done")
        store.markSeen("done")
        #expect(store.nextForYou == nil)
    }

    private func agent(_ name: String, _ id: String, at offset: TimeInterval) -> HookEvent {
        var hook = event(name, at: offset)
        hook.agentID = id
        return hook
    }

    @Test func aStopWaitsForBackgroundSubagents() {
        var store = SessionStore()

        apply(&store, event("UserPromptSubmit"), agent("SubagentStart", "a1", at: 1), event("Stop", at: 5))
        #expect(store.sessions["s1"]?.state == .working)

        apply(&store, agent("PostToolUse", "a1", at: 20), agent("SubagentStop", "a1", at: 60))
        #expect(store.sessions["s1"]?.state == .done)
        #expect(store.sessions["s1"]?.unread == true)
        #expect(store.sessions["s1"]?.runningAgents.isEmpty == true)
    }

    @Test func aForegroundSubagentChangesNothing() {
        var store = SessionStore()

        apply(&store, event("UserPromptSubmit"), agent("SubagentStart", "a1", at: 1), agent("SubagentStop", "a1", at: 4))
        #expect(store.sessions["s1"]?.state == .working)

        apply(&store, event("Stop", at: 5))
        #expect(store.sessions["s1"]?.state == .done)
        #expect(store.sessions["s1"]?.stopDeferred == false)
        #expect(store.sessions["s1"]?.usesBackgroundAgents == false)
    }

    @Test func aSubagentStartingAfterStopMakesDoneWaitLonger() {
        var store = SessionStore()
        store.apply(event("UserPromptSubmit"))
        store.apply(event("Stop", at: 1))
        store.apply(agent("SubagentStart", "a1", at: 2))
        store.apply(agent("SubagentStop", "a1", at: 9))
        #expect(store.sessions["s1"]?.usesBackgroundAgents == true)

        store.apply(event("UserPromptSubmit", at: 20))
        store.apply(event("Stop", at: 21))
        #expect(store.finishPendingStops(now: start.addingTimeInterval(40)).isEmpty)
        #expect(store.finishPendingStops(now: start.addingTimeInterval(41)).count == 1)
    }

    @Test func theStopAfterTheBackgroundAgentAnsweredWaitsOnlyTheShortGrace() {
        var store = SessionStore()
        // PA3 delivers the agent's answer as a new prompt; the agent stops, then the main thread.
        for hook in [event("UserPromptSubmit"), event("Stop", at: 1), agent("SubagentStart", "a1", at: 2),
                     event("UserPromptSubmit", at: 10), agent("SubagentStop", "a1", at: 10), event("Stop", at: 11)] {
            store.apply(hook)
        }
        #expect(store.sessions["s1"]?.usesBackgroundAgents == true)
        #expect(store.finishPendingStops(now: start.addingTimeInterval(13)).isEmpty)
        #expect(store.finishPendingStops(now: start.addingTimeInterval(14)).count == 1)
    }

    @Test func theBackgroundAgentResumingWithoutAPromptIsWorking() {
        var store = SessionStore()
        store.applyAll(event("UserPromptSubmit"), event("Stop", at: 1), agent("SubagentStart", "a1", at: 2),
              event("UserPromptSubmit", at: 10), agent("SubagentStop", "a1", at: 10), event("Stop", at: 11))
        #expect(store.finishPendingStops(now: start.addingTimeInterval(14)).count == 1)

        // A picker answer resumes the agent: no prompt, only its SubagentStart.
        store.applyAll(event("PermissionRequest", at: 20), agent("SubagentStart", "a1", at: 30))
        #expect(store.sessions["s1"]?.state == .working)
        #expect(store.sessions["s1"]?.unread == false)
        #expect(store.sessions["s1"]?.turnWaited == 0)
        #expect(store.finishPendingStops(now: start.addingTimeInterval(200)).isEmpty)

        store.applyAll(event("UserPromptSubmit", at: 300), agent("SubagentStop", "a1", at: 300), event("Stop", at: 301))
        #expect(store.finishPendingStops(now: start.addingTimeInterval(303)).isEmpty)
        #expect(store.finishPendingStops(now: start.addingTimeInterval(304)).count == 1)
        #expect(store.sessions["s1"]?.state == .done)
    }

    @Test func aResumedAgentEndingWithoutAStopFinishesAfterTheShortGrace() {
        var store = SessionStore()
        store.applyAll(event("UserPromptSubmit"), event("Stop", at: 1), agent("SubagentStart", "a1", at: 2),
              event("UserPromptSubmit", at: 10), agent("SubagentStop", "a1", at: 10), event("Stop", at: 11))
        #expect(store.finishPendingStops(now: start.addingTimeInterval(14)).count == 1)

        store.applyAll(agent("SubagentStart", "a1", at: 20), agent("SubagentStop", "a1", at: 50))
        #expect(store.sessions["s1"]?.state == .working)
        #expect(store.finishPendingStops(now: start.addingTimeInterval(52)).isEmpty)
        #expect(store.finishPendingStops(now: start.addingTimeInterval(53)).count == 1)
        #expect(store.sessions["s1"]?.state == .done)
    }

    @Test func aSessionEndClearsSubagentsLeftRunning() {
        var store = SessionStore()

        apply(&store, event("UserPromptSubmit"), agent("SubagentStart", "a1", at: 1), event("Stop", at: 5), event("SessionEnd", at: 9))
        #expect(store.sessions["s1"]?.state == .ended)
        #expect(store.sessions["s1"]?.runningAgents.isEmpty == true)
        #expect(store.sessions["s1"]?.stopDeferred == false)
    }

    @Test func aTempDirectorySessionIsNotTheUsers() {
        var hook = event("SessionStart")
        #expect(!hook.isInTempDirectory)
        hook.cwd = "/private/var/folders/xy/T/te-123"
        #expect(hook.isInTempDirectory)
        hook.cwd = "/tmp/te-1"
        #expect(hook.isInTempDirectory)
    }
}

extension SessionStore {
    /// Applies the event and, for a Stop, lets the grace pass with no subagent starting, as the app's timer does.
    @discardableResult
    mutating func applyAll(_ events: HookEvent...) {
        for event in events { apply(event) }
    }

    mutating func applySettled(_ event: HookEvent) -> Session {
        let session = apply(event)
        guard event.kind == .stop else { return session }
        _ = finishPendingStops(now: event.sentAt.addingTimeInterval(Self.backgroundGrace))
        return sessions[event.sessionID] ?? session
    }
}
