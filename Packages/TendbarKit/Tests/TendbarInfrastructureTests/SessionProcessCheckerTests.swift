import Darwin
import Foundation
import Testing
import TendbarDomain
@testable import TendbarInfrastructure

@Suite struct SessionProcessCheckerTests {
    private var own: ClaudeProcess {
        let info = ProcessTTY.processInfo(getpid())!
        return ClaudeProcess(id: getpid(), startedAt: ProcessTTY.startTime(info))
    }

    @Test func aRunningProcessWithItsStartTimeRuns() {
        let checker = SessionProcessChecker()
        #expect(checker.isRunning(TerminalContext(processID: own.id, processStartedAt: own.startedAt)) == true)
    }

    @Test func aReusedIdIsNotTheSameProcess() {
        let checker = SessionProcessChecker()
        #expect(checker.isRunning(TerminalContext(processID: own.id, processStartedAt: own.startedAt - 3600)) == false)
    }

    @Test func aGoneProcessDoesNotRun() {
        let checker = SessionProcessChecker()
        #expect(checker.isRunning(TerminalContext(processID: 99_999_999, processStartedAt: 1)) == false)
    }

    @Test func withNothingToGoOnItCannotTell() {
        #expect(SessionProcessChecker().isRunning(TerminalContext()) == nil)
    }

    @Test func aMissingTerminalHasNoClaude() {
        #expect(SessionProcessChecker().isRunning(TerminalContext(tty: "/dev/ttys-none")) == false)
    }

    @Test func theNativeInstallIsClaudeByItsPath() {
        #expect(ProcessTTY.isClaude(name: "2.1.325", path: "/Users/a/.local/share/claude/versions/2.1.325"))
        #expect(ProcessTTY.isClaude(name: "node", path: "/opt/homebrew/bin/node"))
        #expect(!ProcessTTY.isClaude(name: "zsh", path: "/bin/zsh"))
    }

    @Test func theProcessSurvivesTheRecord() throws {
        let context = TerminalContext(tty: "/dev/ttys003", processID: 4242, processStartedAt: 1_800_000_000.5)
        let data = try JSONEncoder().encode(TerminalRecord(context))
        #expect(try JSONDecoder().decode(TerminalRecord.self, from: data).context == context)
    }
}
