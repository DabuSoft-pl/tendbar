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

    private func useCase(preview: String? = nil, title: String? = nil, desk: PermissionDesk? = nil, navigator: StubNavigator? = nil) -> HandleHookEvent {
        HandleHookEvent(
            repository: sessions,
            output: sessions,
            alerts: alerts,
            flasher: flasher,
            settings: settings,
            transcripts: StubTranscripts(preview: preview, title: title),
            activity: activity,
            activityOutput: activity,
            desk: desk,
            navigator: navigator
        )
    }

    private func event(_ kind: HookEvent.Kind, at offset: TimeInterval = 0, message: String? = nil) -> HookEvent {
        HookEvent(sessionID: "s1", kind: kind, cwd: "/Users/me/app", transcriptPath: "/tmp/s1.jsonl", message: message, sentAt: now.addingTimeInterval(offset))
    }

    @Test func aBackgroundSubagentHoldsTheDoneAlertUntilItStops() async {
        let handle = useCase()
        var start = event(.subagentStart, at: 1)
        start.agentID = "a1"
        var stop = event(.subagentStop, at: 30)
        stop.agentID = "a1"

        await handle.execute(event(.userPromptSubmit))
        await handle.execute(start)
        await handle.execute(event(.stop, at: 5))
        #expect(alerts.presented.isEmpty)
        #expect(sessions.store.sessions["s1"]?.state == .working)

        await handle.execute(stop)
        #expect(alerts.presented.map(\.0) == [.done])
        #expect(sessions.store.sessions["s1"]?.state == .done)
    }

    @Test func aRunInTheTempDirectoryIsIgnored() async {
        let handle = useCase()
        var hook = event(.userPromptSubmit)
        hook.cwd = "/private/var/folders/ab/T/te-xyz"

        await handle.execute(hook)

        #expect(sessions.store.sessions.isEmpty)
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

    private func desktop(_ kind: HookEvent.Kind, at offset: TimeInterval = 0) -> HookEvent {
        HookEvent(
            sessionID: "s1", kind: kind, cwd: "/Users/me/app", transcriptPath: "/tmp/s1.jsonl",
            terminal: TerminalContext(hostBundleID: TerminalContext.claudeDesktopBundleID, hostSessionID: "local_1"),
            sentAt: now.addingTimeInterval(offset)
        )
    }

    @Test func aClaudeDesktopSessionLeavesBannersAndPromptsToTheApp() async {
        settings.alertSettings.answersPermissions = true
        let desk = PermissionDesk(alerts: alerts)
        let handle = useCase(desk: desk)
        let reply = RecordingReply()
        let ask = PermissionAsk(id: "a1", sessionID: "s1", tool: "Bash", detail: "date")

        await handle.execute(desktop(.permissionRequest), permission: (ask, reply))
        await handle.execute(desktop(.stop, at: 1))

        #expect(alerts.presented.isEmpty)
        #expect(alerts.permissions.isEmpty)
        #expect(reply.answers == [nil])
        #expect(flasher.tones == [.attention, .success])
        #expect(sessions.store.sessions["s1"]?.state == .done)
    }

    @Test func claudeDesktopBannersComeBackWhenTurnedOn() async {
        settings.alertSettings.leavesClaudeDesktopBanners = false
        let handle = useCase()

        await handle.execute(desktop(.stop))

        #expect(alerts.presented.map(\.0) == [.done])
    }

    @Test func aSessionInFrontOnlyGlows() async {
        settings.alertSettings.answersPermissions = true
        let navigator = StubNavigator()
        navigator.inFront = true
        let reply = RecordingReply()
        let handle = useCase(desk: PermissionDesk(alerts: alerts), navigator: navigator)

        await handle.execute(event(.permissionRequest), permission: (PermissionAsk(id: "a1", sessionID: "s1", tool: "Bash", detail: "date"), reply))
        await handle.execute(event(.stop, at: 1))

        #expect(alerts.presented.isEmpty)
        #expect(alerts.permissions.isEmpty)
        #expect(reply.answers == [nil])
        #expect(flasher.tones == [.attention, .success])
    }

    @Test func aSessionInFrontStillGetsBannersWhenTurnedOff() async {
        settings.alertSettings.glowOnlyInFront = false
        let navigator = StubNavigator()
        navigator.inFront = true
        let handle = useCase(navigator: navigator)

        await handle.execute(event(.stop))

        #expect(alerts.presented.map(\.0) == [.done])
    }

    @Test func aFocusKeepsTheBannerButSilencesTendbar() async {
        settings.alertSettings.quietForFocus = true
        let handle = useCase()

        await handle.execute(event(.stop))

        #expect(alerts.presented.map(\.0) == [.done])
        #expect(alerts.sounds == [AlertSound.none])
        #expect(flasher.tones.isEmpty)
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

    @Test func aRequestNotShownWholeCanOnlyBeDenied() async {
        settings.alertSettings.answersPermissions = true
        let desk = PermissionDesk(alerts: alerts)
        let handle = useCase(desk: desk)
        let reply = RecordingReply()
        let ask = PermissionAsk(id: "a1", sessionID: "s1", tool: "Write", detail: "/tmp/x", shownInFull: false)

        await handle.execute(event(.permissionRequest), permission: (ask, reply))

        #expect(!desk.answer(askID: "a1", sessionID: "s1", decision: .allow))
        #expect(desk.isWaiting(sessionID: "s1"))
        #expect(desk.answer(askID: "a1", sessionID: "s1", decision: .deny))
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

    @Test func aWaitingPromptShowsInThePanelUntilItIsAnswered() async {
        settings.alertSettings.answersPermissions = true
        let output = RecordingPermissions()
        let desk = PermissionDesk(alerts: alerts, output: output)
        let handle = useCase(desk: desk)
        let ask = PermissionAsk(id: "a1", sessionID: "s1", tool: "Bash", detail: "touch test.txt", shownInFull: true)

        await handle.execute(event(.permissionRequest), permission: (ask, RecordingReply()))
        #expect(output.shown.last == [ask])
        desk.answer(askID: "a1", sessionID: "s1", decision: .allow)

        #expect(output.shown.last == [])
        #expect(alerts.dismissed.contains("s1"))
    }

    @Test func aPromptAnsweredInTheTerminalLeavesThePanel() async {
        settings.alertSettings.answersPermissions = true
        let output = RecordingPermissions()
        let desk = PermissionDesk(alerts: alerts, output: output)
        let handle = useCase(desk: desk)

        await handle.execute(event(.permissionRequest), permission: (PermissionAsk(id: "a1", sessionID: "s1", tool: "Bash"), RecordingReply()))
        await handle.execute(event(.postToolUse, at: 9))
        await handle.execute(event(.stop, at: 12))

        #expect(output.shown.map(\.count) == [1, 0])
    }
}
