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
}
