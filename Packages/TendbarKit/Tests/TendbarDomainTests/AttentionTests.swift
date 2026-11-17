import Foundation
import Testing
@testable import TendbarDomain

@Suite struct AttentionTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let minute: TimeInterval = 60

    private func event(_ name: String, at minutes: Double, session: String = "s1") -> HookEvent {
        HookEvent(
            sessionID: session,
            kind: HookEvent.Kind(name: name),
            cwd: "/Users/me/code/app",
            sentAt: start.addingTimeInterval(minutes * minute)
        )
    }

    private func store(_ events: HookEvent...) -> SessionStore {
        var store = SessionStore()
        for event in events { store.applySettled(event) }
        return store
    }

    @Test func aWaitRemembersWhenItStartedAndAddsUpInTheTurn() {
        var store = store(event("UserPromptSubmit", at: 0), event("PermissionRequest", at: 2))
        #expect(store.sessions["s1"]?.waitingSince == start.addingTimeInterval(2 * minute))

        store.apply(event("PostToolUse", at: 5))
        #expect(store.sessions["s1"]?.waitingSince == nil)
        #expect(store.sessions["s1"]?.turnWaited == 3 * minute)
    }

    @Test func remindsOnceAfterTheDelay() {
        var store = store(event("UserPromptSubmit", at: 0), event("PermissionRequest", at: 1))
        let after = 5 * minute

        #expect(Attention.dueReminders(in: store, now: start.addingTimeInterval(4 * minute), after: after).isEmpty)
        let due = Attention.dueReminders(in: store, now: start.addingTimeInterval(6 * minute), after: after)
        #expect(due.map(\.id) == ["s1"])

        store.markReminded("s1")
        #expect(Attention.dueReminders(in: store, now: start.addingTimeInterval(20 * minute), after: after).isEmpty)
    }

    @Test func aNewWaitCanBeRemindedAgain() {
        var store = store(event("UserPromptSubmit", at: 0), event("PermissionRequest", at: 1))
        store.markReminded("s1")
        store.apply(event("PostToolUse", at: 2))
        store.apply(event("PermissionRequest", at: 3))

        #expect(store.sessions["s1"]?.remindedWait == false)
        #expect(Attention.dueReminders(in: store, now: start.addingTimeInterval(9 * minute), after: 5 * minute).count == 1)
    }

    @Test func aWorkingSessionGoesQuietWithoutEvents() {
        var store = store(event("UserPromptSubmit", at: 0), event("PostToolUse", at: 3))
        let after = 15 * minute

        #expect(Attention.newlyQuiet(in: store, now: start.addingTimeInterval(10 * minute), after: after).isEmpty)
        #expect(Attention.newlyQuiet(in: store, now: start.addingTimeInterval(19 * minute), after: after).map(\.id) == ["s1"])

        store.markQuiet("s1")
        #expect(Attention.newlyQuiet(in: store, now: start.addingTimeInterval(30 * minute), after: after).isEmpty)

        store.apply(event("PostToolUse", at: 31))
        #expect(store.sessions["s1"]?.flaggedQuiet == false)
    }

    @Test func onlyWorkingSessionsGoQuiet() {
        let store = store(event("UserPromptSubmit", at: 0), event("Stop", at: 1))

        #expect(Attention.newlyQuiet(in: store, now: start.addingTimeInterval(60 * minute), after: 15 * minute).isEmpty)
    }
}
