import Foundation
import Testing
import TendbarDomain
@testable import TendbarInfrastructure

@Suite struct HookEnvelopeTests {
    @Test func capturesTheClaudeDesktopSessionAndStoresIt() throws {
        let context = TerminalContext.capture(
            environment: ["__CFBundleIdentifier": "com.anthropic.claudefordesktop", "CLAUDE_CODE_HOST_SESSION_ID": "local_abc-123"],
            tty: nil
        )
        let stored = try JSONDecoder().decode(TerminalRecord.self, from: JSONEncoder().encode(TerminalRecord(context)))

        #expect(context.hostSessionID == "local_abc-123")
        #expect(stored.context == context)
    }

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
        #expect(event.message == "API overloaded (529 Overloaded)")
        #expect(!redacted.contains("last_assistant_message"))
    }

    @Test func fallsBackToAGenericLineForUnknownTypes() throws {
        let payload = try JSONDecoder().decode(HookPayload.self, from: Data(#"{"session_id":"s1","hook_event_name":"StopFailure","error":"something_new"}"#.utf8))

        #expect(payload.failureMessage == "API error")
    }

    @Test func aPermissionPromptKeepsItsToolAndCommand() throws {
        let input = Data(#"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"Clean"}}"#.utf8)

        let record = try #require(PermissionRecord(hookInput: input, id: "a1"))

        #expect(record == PermissionRecord(id: "a1", tool: "Bash", detail: "rm -rf build", shownInFull: true))
        #expect(PermissionRecord(hookInput: Data(#"{"hook_event_name":"Stop","session_id":"s1"}"#.utf8)) == nil)
    }

    @Test func aFileEditShowsItsPathAndLongCommandsAreCapped() throws {
        let edit = Data(#"{"hook_event_name":"PermissionRequest","tool_name":"Edit","tool_input":{"file_path":"/Users/me/app/a.swift","old_string":"x"}}"#.utf8)
        let long = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest", "tool_name": "Bash",
            "tool_input": ["command": String(repeating: "a", count: 5_000)],
        ])

        #expect(PermissionRecord(hookInput: edit)?.detail == "/Users/me/app/a.swift")
        #expect(PermissionRecord(hookInput: edit)?.shownInFull == false)
        #expect(PermissionRecord(hookInput: long)?.detail?.count == PermissionRecord.detailLimit)
        #expect(PermissionRecord(hookInput: long)?.shownInFull == false)
    }

    private func permission(_ tool: String, _ input: [String: Any]) throws -> PermissionRecord? {
        PermissionRecord(hookInput: try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest", "tool_name": tool, "tool_input": input,
        ]))
    }

    @Test func onlyARequestShownWholeCanBeAllowed() throws {
        let tail = String(repeating: "a", count: PermissionRecord.detailLimit) + "; echo MARKER"
        let long = try #require(try permission("Bash", ["command": tail]))
        #expect(long.detail?.contains("MARKER") == false)
        #expect(!long.shownInFull)

        #expect(try permission("Bash", ["command": "make test", "description": "Run tests", "timeout": 60])?.shownInFull == true)
        #expect(try permission("Read", ["file_path": "/tmp/a", "offset": 1, "limit": 20])?.shownInFull == true)
        #expect(try permission("Write", ["file_path": "/tmp/x", "content": "MARKER"])?.shownInFull == false)
        #expect(try permission("Bash", ["command": "ls", "dangerouslyDisableSandbox": true])?.shownInFull == false)

        let mcp = try #require(try permission("mcp__dummy__act", ["arg": "MARKER"]))
        #expect(mcp.detail == nil)
        #expect(!mcp.shownInFull)
        #expect(!mcp.ask(sessionID: "s1").offers(.allow))
        #expect(mcp.ask(sessionID: "s1").offers(.deny))
    }

    @Test func aRecordWithoutTheFlagCannotBeAllowed() throws {
        let old = try JSONDecoder().decode(PermissionRecord.self, from: Data(#"{"id":"a1","tool":"Bash","detail":"ls"}"#.utf8))

        #expect(!old.shownInFull)
    }

    @Test func answersBecomeHookOutput() throws {
        #expect(PermissionAnswer.decode(PermissionAnswer.encode(.allow)) == .allow)
        #expect(PermissionAnswer.decode(PermissionAnswer.encode(nil)) == nil)

        let output = try JSONSerialization.jsonObject(with: PermissionAnswer.hookOutput(.deny)) as? [String: Any]
        let specific = output?["hookSpecificOutput"] as? [String: Any]
        let decision = specific?["decision"] as? [String: Any]
        #expect(specific?["hookEventName"] as? String == "PermissionRequest")
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] != nil)
    }
}
