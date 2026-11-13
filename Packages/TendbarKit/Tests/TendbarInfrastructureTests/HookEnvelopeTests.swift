import Foundation
import Testing
import TendbarDomain
@testable import TendbarInfrastructure

@Suite struct HookEnvelopeTests {
    @Test func decodesNotificationPayload() throws {
        let raw = """
        {"session_id":"abc-123","transcript_path":"/Users/me/.claude/projects/x/abc-123.jsonl","cwd":"/Users/me/code/app","hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt","permission_mode":"default"}
        """
        let envelope = HookEnvelope(sentAt: Date(), terminal: TerminalContext(), raw: raw)

        let payload = try envelope.payload()

        #expect(payload.sessionID == "abc-123")
        #expect(payload.event == "Notification")
        #expect(payload.cwd == "/Users/me/code/app")
        #expect(payload.notificationType == "permission_prompt")
        #expect(payload.message == "Claude needs your permission to use Bash")
    }

    @Test func decodesStopPayloadWithoutOptionalFields() throws {
        let raw = #"{"session_id":"s1","hook_event_name":"Stop","stop_hook_active":false}"#

        let payload = try HookEnvelope(sentAt: Date(), terminal: TerminalContext(), raw: raw).payload()

        #expect(payload.event == "Stop")
        #expect(payload.cwd == nil)
        #expect(payload.message == nil)
    }

    @Test func rejectsPayloadWithoutSession() {
        let envelope = HookEnvelope(sentAt: Date(), terminal: TerminalContext(), raw: #"{"hook_event_name":"Stop"}"#)

        #expect(throws: DecodingError.self) { try envelope.payload() }
    }

    @Test func roundTripsThroughEncoder() throws {
        let envelope = HookEnvelope(
            sentAt: Date(timeIntervalSince1970: 1_800_000_000),
            terminal: TerminalContext(program: "iTerm.app", itermSessionID: "w0t1p0:ABC", tty: "/dev/ttys004", configDirectory: "/Users/me/.claude-work"),
            raw: #"{"session_id":"s1","hook_event_name":"Stop"}"#
        )

        let data = try HookEnvelope.encoder.encode(envelope)
        let decoded = try HookEnvelope.decoder.decode(HookEnvelope.self, from: data)

        #expect(decoded == envelope)
    }

    @Test func capturesTerminalFromEnvironment() {
        let context = TerminalContext.capture(
            environment: ["TERM_PROGRAM": "Apple_Terminal", "TERM_SESSION_ID": "T-1", "CLAUDE_CONFIG_DIR": "/Users/me/.claude-work"],
            tty: "/dev/ttys001"
        )

        #expect(context.program == "Apple_Terminal")
        #expect(context.terminalSessionID == "T-1")
        #expect(context.itermSessionID == nil)
        #expect(context.configDirectory == "/Users/me/.claude-work")
        #expect(context.tty == "/dev/ttys001")
    }

    @Test func capturesTerminalSpecificIDs() {
        let context = TerminalContext.capture(
            environment: [
                "TERM_PROGRAM": "tmux", "__CFBundleIdentifier": "com.github.wez.wezterm", "WEZTERM_PANE": "2",
                "KITTY_WINDOW_ID": "5", "KITTY_LISTEN_ON": "unix:/tmp/k", "TMUX": "/private/tmp/tmux-501/default,812,0",
                "TMUX_PANE": "%3",
            ],
            tty: nil
        )

        #expect(context.hostBundleID == "com.github.wez.wezterm")
        #expect(context.weztermPane == "2")
        #expect(context.kittyWindowID == "5")
        #expect(context.kittySocket == "unix:/tmp/k")
        #expect(context.tmuxSocket == "/private/tmp/tmux-501/default")
        #expect(context.tmuxPane == "%3")
    }

    @Test func socketPathHonoursOverride() {
        #expect(TendbarPaths.socketPath(environment: ["TENDBAR_SOCKET": "/tmp/x.sock"]) == "/tmp/x.sock")
        #expect(TendbarPaths.socketPath(environment: [:]).hasSuffix("Tendbar/tendbar.sock"))
    }
}

@Suite struct InboundMessageTests {
    @Test func mapsAHookIntoADomainEvent() {
        let envelope = HookEnvelope(
            sentAt: Date(timeIntervalSince1970: 1_800_000_000),
            terminal: TerminalContext(program: "iTerm.app", tty: "/dev/ttys001"),
            raw: #"{"session_id":"s1","hook_event_name":"Notification","cwd":"/Users/me/app","message":"Allow Bash?","notification_type":"permission_prompt"}"#
        )

        #expect(envelope.message() == .hook(HookEvent(
            sessionID: "s1",
            kind: .notification,
            cwd: "/Users/me/app",
            message: "Allow Bash?",
            notificationType: "permission_prompt",
            terminal: TerminalContext(program: "iTerm.app", tty: "/dev/ttys001"),
            sentAt: Date(timeIntervalSince1970: 1_800_000_000)
        )))
    }

    @Test func keepsUnknownEventsAsOther() {
        let envelope = HookEnvelope(sentAt: Date(), terminal: TerminalContext(), raw: #"{"session_id":"s1","hook_event_name":"PreCompact"}"#)

        guard case let .hook(event) = envelope.message() else {
            Issue.record("expected a hook event")
            return
        }
        #expect(event.kind == .other("PreCompact"))
    }
}

@Suite struct StopFailureMessageTests {
    @Test func describesTheErrorTypeAndDetails() throws {
        let raw = #"{"session_id":"s1","hook_event_name":"StopFailure","error":"overloaded","error_details":"529 Overloaded","last_assistant_message":"API Error"}"#
        let redacted = HookRedaction.redact(Data(raw.utf8), statusLine: false)
        let envelope = HookEnvelope(sentAt: Date(), terminal: TerminalContext(), raw: redacted)

        guard case let .hook(event) = try #require(envelope.message()) else { Issue.record("not a hook"); return }
        #expect(event.kind == .stopFailure)
        #expect(event.message == "Przeciążone API (529 Overloaded)")
        #expect(!redacted.contains("last_assistant_message"))
    }

    @Test func fallsBackToAGenericLineForUnknownTypes() throws {
        let payload = try JSONDecoder().decode(HookPayload.self, from: Data(#"{"session_id":"s1","hook_event_name":"StopFailure","error":"something_new"}"#.utf8))

        #expect(payload.failureMessage == "Błąd API")
    }
}
