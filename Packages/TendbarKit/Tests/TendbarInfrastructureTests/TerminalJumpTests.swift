import Testing
import TendbarDomain
@testable import TendbarInfrastructure

@Suite struct TerminalJumpTests {
    @Test func iTermMatchesTheUniqueIDAndTTY() {
        let plan = TerminalJump.plan(for: TerminalContext(
            program: "iTerm.app",
            itermSessionID: "w0t1p0:F6D8A128-8174-4425-AC0D-37C2BC683C97",
            tty: "/dev/ttys001"
        ))

        guard case let .script(script, bundleID) = plan else {
            Issue.record("expected a script, got \(plan)")
            return
        }
        #expect(bundleID == TerminalJump.iTerm)
        #expect(script.contains(#"unique id of s is "F6D8A128-8174-4425-AC0D-37C2BC683C97""#))
        #expect(script.contains(#"tty of s is "/dev/ttys001""#))
        #expect(script.contains("select s"))
    }

    @Test func terminalMatchesTheTTY() {
        let plan = TerminalJump.plan(for: TerminalContext(program: "Apple_Terminal", terminalSessionID: "X", tty: "/dev/ttys004"))

        guard case let .script(script, bundleID) = plan else {
            Issue.record("expected a script, got \(plan)")
            return
        }
        #expect(bundleID == TerminalJump.terminal)
        #expect(script.contains(#"tty of t is "/dev/ttys004""#))
    }

    @Test func terminalWithoutTTYOnlyActivates() {
        #expect(TerminalJump.plan(for: TerminalContext(program: "Apple_Terminal")) == .activate(bundleID: TerminalJump.terminal))
    }

    @Test func otherKnownTerminalsActivate() {
        #expect(TerminalJump.plan(for: TerminalContext(program: "vscode", tty: "/dev/ttys002")) == .activate(bundleID: "com.microsoft.VSCode"))
        #expect(TerminalJump.plan(for: TerminalContext(program: "ghostty")) == .activate(bundleID: "com.mitchellh.ghostty"))
    }

    @Test func claudeDesktopOpensItsSessionLink() {
        let desktop = TerminalContext(hostBundleID: TerminalJump.claudeDesktop, hostSessionID: "local_35334b64-8d2a-46d2-b9e4-00192d0674d9")

        #expect(TerminalJump.plan(for: desktop) == .openURL(
            "claude://code/continue?session=local_35334b64-8d2a-46d2-b9e4-00192d0674d9", bundleID: TerminalJump.claudeDesktop
        ))
    }

    @Test func claudeDesktopWithoutAValidSessionOnlyActivates() {
        for id in [nil, "local_", "local_x&y=1", "session_abc", "local_" + String(repeating: "a", count: 65)] {
            let plan = TerminalJump.plan(for: TerminalContext(hostBundleID: TerminalJump.claudeDesktop, hostSessionID: id))
            #expect(plan == .activate(bundleID: TerminalJump.claudeDesktop))
        }
    }

    @Test func unknownTerminalIsUnavailable() {
        #expect(TerminalJump.plan(for: TerminalContext(program: "tmux", tty: "/dev/ttys002")) == .unavailable)
        #expect(TerminalJump.plan(for: TerminalContext()) == .unavailable)
    }

    @Test func refusesValuesThatCouldBreakTheScript() {
        let plan = TerminalJump.plan(for: TerminalContext(
            program: "iTerm.app",
            itermSessionID: #"w0:x" then do shell script "rm -rf ~" --"#,
            tty: #"/dev/ttys001" or true --"#
        ))

        #expect(plan == .activate(bundleID: TerminalJump.iTerm))
    }

    static let tools = TerminalTools { "/usr/local/bin/\($0)" }

    @Test func hostBundleIDWinsOverTheProgramName() {
        let plan = TerminalJump.plan(
            for: TerminalContext(program: "vscode", hostBundleID: "com.todesktop.230313mzl4w4u92"),
            folder: "/Users/me/app"
        )
        #expect(plan == .openFolder("/Users/me/app", bundleID: "com.todesktop.230313mzl4w4u92"))
    }

    @Test func vsCodeOpensTheSessionFolder() {
        #expect(TerminalJump.plan(for: TerminalContext(program: "vscode"), folder: "/Users/me/app") == .openFolder("/Users/me/app", bundleID: TerminalJump.vsCode))
        #expect(TerminalJump.plan(for: TerminalContext(program: "vscode"), folder: "relative") == .activate(bundleID: TerminalJump.vsCode))
    }

    @Test func wezTermActivatesThePane() {
        let plan = TerminalJump.plan(
            for: TerminalContext(program: "WezTerm", weztermPane: "7", weztermSocket: "/Users/me/.local/share/wezterm/sock"),
            tools: Self.tools
        )
        #expect(plan == .command(
            TerminalCommand("/usr/local/bin/wezterm", ["cli", "activate-pane", "--pane-id", "7"],
                            environment: ["WEZTERM_UNIX_SOCKET": "/Users/me/.local/share/wezterm/sock"]),
            bundleID: TerminalJump.wezTerm
        ))
    }

    @Test func wezTermWithoutItsToolOnlyActivates() {
        #expect(TerminalJump.plan(for: TerminalContext(program: "WezTerm", weztermPane: "7")) == .activate(bundleID: TerminalJump.wezTerm))
    }

    @Test func kittyFocusesTheWindowThroughItsSocket() {
        let plan = TerminalJump.plan(
            for: TerminalContext(kittyWindowID: "3", kittySocket: "unix:/tmp/kitty-501"),
            tools: Self.tools
        )
        #expect(plan == .command(
            TerminalCommand("/usr/local/bin/kitty", ["@", "--to", "unix:/tmp/kitty-501", "focus-window", "--match", "id:3"]),
            bundleID: TerminalJump.kitty
        ))
    }

    @Test func kittyWithoutRemoteControlOnlyActivates() {
        #expect(TerminalJump.plan(for: TerminalContext(kittyWindowID: "3"), tools: Self.tools) == .activate(bundleID: TerminalJump.kitty))
    }

    @Test func tmuxSelectsThePaneAndKeepsTheHostTerminal() {
        let plan = TerminalJump.plan(
            for: TerminalContext(program: "tmux", hostBundleID: TerminalJump.iTerm, itermSessionID: "w0t0p0:OLD",
                                 tty: "/dev/ttys009", tmuxPane: "%4", tmuxSocket: "/private/tmp/tmux-501/default"),
            tools: Self.tools
        )
        guard case let .tmux(target) = plan else {
            Issue.record("expected tmux, got \(plan)")
            return
        }
        #expect(target.pane == "%4")
        #expect(target.selectCommands.first == TerminalCommand("/usr/local/bin/tmux", ["-S", "/private/tmp/tmux-501/default", "select-window", "-t", "%4"]))
        #expect(target.host.itermSessionID == nil)
        #expect(target.host.tty == nil)

        let host = TerminalJump.plan(for: target.host(clientTTY: "/dev/ttys002"))
        guard case let .script(script, bundleID) = host else {
            Issue.record("expected a script, got \(host)")
            return
        }
        #expect(bundleID == TerminalJump.iTerm)
        #expect(script.contains(#"tty of s is "/dev/ttys002""#))
    }

    @Test func tmuxLooksUpTheClientOfThePaneSession() {
        let target = TmuxTarget(executable: "/t", socket: "/s", pane: "%1", host: TerminalContext())
        let runner = FakeRunner(outputs: ["display-message": "work\n", "list-clients": "/dev/ttys005\n"])

        #expect(target.select(using: runner) == "/dev/ttys005")
        #expect(runner.ran.contains(["-S", "/s", "list-clients", "-t", "work", "-F", "#{client_tty}"]))
    }

    @Test func refusesPaneIDsThatAreNotNumbers() {
        #expect(TerminalJump.plan(for: TerminalContext(program: "WezTerm", weztermPane: "7; rm"), tools: Self.tools) == .activate(bundleID: TerminalJump.wezTerm))
        #expect(TerminalJump.plan(for: TerminalContext(tmuxPane: "%x", tmuxSocket: "/s"), tools: Self.tools) == .unavailable)
    }
}

final class FakeRunner: CommandRunning, @unchecked Sendable {
    let outputs: [String: String]
    private(set) var ran: [[String]] = []

    init(outputs: [String: String]) {
        self.outputs = outputs
    }

    func run(_ command: TerminalCommand) -> CommandResult {
        ran.append(command.arguments)
        let verb = command.arguments.dropFirst(2).first ?? ""
        return CommandResult(status: 0, output: outputs[verb] ?? "")
    }
}
