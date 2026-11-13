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
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func useCase(preview: String? = nil) -> HandleHookEvent {
        HandleHookEvent(
            repository: sessions,
            output: sessions,
            alerts: alerts,
            flasher: flasher,
            settings: settings,
            transcripts: StubTranscripts(preview: preview)
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
}
