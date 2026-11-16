import Testing
import TendbarDomain
@testable import TendbarInfrastructure

@Suite struct TerminalFrontTests {
    private let tools = TerminalTools { "/usr/local/bin/\($0)" }

    @Test func iTermAsksForTheCurrentSession() {
        let check = TerminalFront.check(for: TerminalContext(program: "iTerm.app", itermSessionID: "w0t1p0:ABC-1", tty: "/dev/ttys001"))
        guard case let .script(script, bundleID) = check else { Issue.record("expected a script"); return }
        #expect(bundleID == TerminalJump.iTerm)
        #expect(script.contains("current session of current window"))
        #expect(script.contains(#"unique id of s is "ABC-1""#))
    }

    @Test func terminalAsksForTheSelectedTab() {
        let check = TerminalFront.check(for: TerminalContext(program: "Apple_Terminal", tty: "/dev/ttys002"))
        guard case let .script(script, _) = check else { Issue.record("expected a script"); return }
        #expect(script.contains(#"tty of selected tab of front window is "/dev/ttys002""#))
    }

    @Test func vsCodeAndTheClaudeAppOnlyKnowTheApp() {
        guard case .app(TerminalJump.vsCode) = TerminalFront.check(for: TerminalContext(program: "vscode")) else { Issue.record("vscode"); return }
        let desktop = TerminalContext(hostBundleID: TerminalContext.claudeDesktopBundleID)
        guard case .app(TerminalJump.claudeDesktop) = TerminalFront.check(for: desktop) else { Issue.record("desktop"); return }
    }

    @Test func noAppMeansUnknown() {
        guard case .unknown = TerminalFront.check(for: TerminalContext()) else { Issue.record("expected unknown"); return }
    }

    @Test func tmuxWantsTheActivePaneOfTheActiveWindow() {
        let context = TerminalContext(program: "iTerm.app", tmuxPane: "%3", tmuxSocket: "/tmp/tmux-501/default")
        guard case let .command(command, bundleID, isFront) = TerminalFront.check(for: context, tools: tools) else { Issue.record("expected a command"); return }
        #expect(bundleID == TerminalJump.iTerm)
        #expect(command.arguments.suffix(3) == ["-t", "%3", "#{window_active}#{pane_active}"])
        #expect(isFront("11\n"))
        #expect(!isFront("10\n"))
    }

    @Test func weztermReadsTheFocusedPane() {
        let output = #"[{"focused_pane_id": 7}, {"focused_pane_id": 2}]"#
        #expect(TerminalFront.weztermFocuses(pane: "2", in: output))
        #expect(!TerminalFront.weztermFocuses(pane: "3", in: output))
        #expect(!TerminalFront.weztermFocuses(pane: "2", in: "not json"))
    }

    @Test func kittyReadsTheFocusedWindow() {
        let output = #"[{"tabs": [{"windows": [{"id": 1, "is_focused": false}, {"id": 4, "is_focused": true}]}]}]"#
        #expect(TerminalFront.kittyFocuses(window: "4", in: output))
        #expect(!TerminalFront.kittyFocuses(window: "1", in: output))
    }
}
