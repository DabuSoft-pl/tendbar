import Foundation
import Testing
import TendbarApplication
import TendbarDomain

@MainActor
@Suite struct HandleHookEventTests {
    let sessions = InMemorySessions()
    let alerts = RecordingAlerts()
    let flasher = RecordingFlasher()
    let settings = StubSettings()
    let activity = InMemoryActivity()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func useCase(preview: String? = nil, title: String? = nil, desk: PermissionDesk? = nil) -> HandleHookEvent {
        HandleHookEvent(
            repository: sessions,
            output: sessions,
            alerts: alerts,
            flasher: flasher,
            settings: settings,
            transcripts: StubTranscripts(preview: preview, title: title),
            activity: activity,
            activityOutput: activity,
            desk: desk
        )
    }

    private func event(_ kind: HookEvent.Kind, at offset: TimeInterval = 0, message: String? = nil) -> HookEvent {
        HookEvent(sessionID: "s1", kind: kind, cwd: "/Users/me/app", transcriptPath: "/tmp/s1.jsonl", message: message, sentAt: now.addingTimeInterval(offset))
    }

    @Test func aFinishedTurnShowsTheReplyAndFlashesGreen() async {
        settings.alertSettings.showsReplyPreview = true
        let handle = useCase(preview: "Gotowe: testy przechodzą")

        await handle.execute(event(.userPromptSubmit))
        await handle.execute(event(.stop, at: 1))

        #expect(alerts.presented.map(\.0) == [.done])
        #expect(alerts.presented.first?.1.preview == "Gotowe: testy przechodzą")
        #expect(flasher.tones == [.success])
        #expect(sessions.store.sessions["s1"]?.state == .done)
        #expect(sessions.shown.last == sessions.store)
    }

    @Test func theBannerIsNamedAfterClaudesTitle() async {
        await useCase(title: "Diff warstwy UI").execute(event(.stop))

        #expect(sessions.store.sessions["s1"]?.title == "Diff warstwy UI")
        #expect(alerts.presented.first?.1.displayName == "Diff warstwy UI")
    }

    @Test func withoutATitleTheFolderNamesTheSession() async {
        await useCase().execute(event(.stop))

        #expect(alerts.presented.first?.1.displayName == "app")
    }

    @Test func aDoneBannerLeavesTheReplyOutByDefault() async {
        await useCase(preview: "tajny plan").execute(event(.stop))

        #expect(alerts.presented.map(\.0) == [.done])
        #expect(alerts.presented.first?.1.preview == nil)
        #expect(sessions.store.sessions["s1"]?.preview == "tajny plan")
    }

    @Test func noGreenFlashWhenTheUserTurnedItOff() async {
        settings.alertSettings.flashOnDone = false

        await useCase().execute(event(.stop))

        #expect(alerts.presented.map(\.0) == [.done])
        #expect(flasher.tones.isEmpty)
    }

    @Test func aMutedFolderStaysQuietButStillChangesState() async {
        settings.alertSettings.mutedFolders = ["/Users/me/app"]

        await useCase().execute(event(.permissionRequest))
        await useCase().execute(event(.stop, at: 1))

        #expect(alerts.presented.isEmpty)
        #expect(flasher.tones.isEmpty)
        #expect(sessions.store.sessions["s1"]?.state == .done)
        #expect(sessions.store.sessions["s1"]?.unread == true)
    }

    @Test func aFinishedTurnIsCountedForToday() async {
        let handle = useCase()

        await handle.execute(event(.userPromptSubmit))
        await handle.execute(event(.stop, at: 120))

        #expect(activity.stats.day(of: now, calendar: .current).turns == 1)
        #expect(activity.shown.count == 1)
    }

    @Test func nothingAtAllWhenTheKindIsSwitchedOff() async {
        settings.alertSettings.notifyNeedsYou = false

        await useCase().execute(event(.permissionRequest))

        #expect(alerts.presented.isEmpty)
        #expect(flasher.tones.isEmpty)
        #expect(sessions.store.sessions["s1"]?.state == .needsYou)
    }

    @Test func aPermissionPromptAlertsOnceAndFlashesOrange() async {
        let handle = useCase()

        await handle.execute(event(.permissionRequest))
        await handle.execute(HookEvent(sessionID: "s1", kind: .notification, message: "Allow Bash?", notificationType: "permission_prompt", sentAt: now))

        #expect(alerts.presented.map(\.0) == [.needsYou])
        #expect(flasher.tones == [.attention])
    }

    @Test func workingAgainClearsTheBanner() async {
        let handle = useCase()

        await handle.execute(event(.permissionRequest))
        await handle.execute(event(.postToolUse, at: 1))

        #expect(alerts.dismissed == ["s1"])
    }

    @Test func aPermissionPromptGoesToTheBannerOnlyWhenTurnedOn() async {
        let desk = PermissionDesk(alerts: alerts)
        let handle = useCase(desk: desk)
        let reply = RecordingReply()
        let ask = PermissionAsk(id: "a1", sessionID: "s1", tool: "Bash", detail: "rm -rf build")

        await handle.execute(event(.permissionRequest), permission: (ask, reply))

        #expect(reply.answers == [nil])
        #expect(alerts.presented.map(\.0) == [.needsYou])
        #expect(alerts.permissions.isEmpty)
    }

    @Test func theBannerAnswersTheHookOnce() async {
        settings.alertSettings.answersPermissions = true
        let desk = PermissionDesk(alerts: alerts)
        let handle = useCase(desk: desk)
        let reply = RecordingReply()
        let ask = PermissionAsk(id: "a1", sessionID: "s1", tool: "Bash", detail: "rm -rf build")

        await handle.execute(event(.permissionRequest), permission: (ask, reply))

        #expect(reply.answers.isEmpty)
        #expect(alerts.permissions == [ask])
        #expect(!desk.answer(askID: "old", sessionID: "s1", decision: .allow))
        #expect(desk.answer(askID: "a1", sessionID: "s1", decision: .deny))
        #expect(!desk.answer(askID: "a1", sessionID: "s1", decision: .allow))
        #expect(reply.answers == [.deny])
    }

    @Test func answeringInTheTerminalReleasesTheHook() async {
        settings.alertSettings.answersPermissions = true
        let desk = PermissionDesk(alerts: alerts)
        let handle = useCase(desk: desk)
        let reply = RecordingReply()

        await handle.execute(event(.permissionRequest), permission: (PermissionAsk(id: "a1", sessionID: "s1", tool: "Bash"), reply))
        await handle.execute(event(.notification, at: 6, message: "Claude needs your permission to use Bash"))
        #expect(reply.answers.isEmpty)
        await handle.execute(event(.postToolUse, at: 9))

        #expect(reply.answers == [nil])
        #expect(!desk.isWaiting(sessionID: "s1"))
    }

    @Test func aSubagentsToolUseDoesNotEndTheMainThreadsWait() async {
        settings.alertSettings.answersPermissions = true
        let desk = PermissionDesk(alerts: alerts)
        let handle = useCase(desk: desk)
        let reply = RecordingReply()

        await handle.execute(event(.permissionRequest), permission: (PermissionAsk(id: "a1", sessionID: "s1", tool: "Bash"), reply))
        var fromSubagent = event(.postToolUse, at: 2)
        fromSubagent.agentID = "agent-7"
        await handle.execute(fromSubagent)

        #expect(sessions.load().sessions["s1"]?.state == .needsYou)
        #expect(desk.isWaiting(sessionID: "s1"))
        #expect(reply.answers.isEmpty)
    }
}
