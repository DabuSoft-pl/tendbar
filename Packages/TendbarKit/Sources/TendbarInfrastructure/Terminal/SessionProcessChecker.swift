import Foundation
import TendbarApplication
import TendbarDomain

/// Looks the session's Claude Code process up by id and start time; older sessions without one by their terminal.
public struct SessionProcessChecker: SessionProcessChecking {
    public init() {}

    public func isRunning(_ terminal: TerminalContext) -> Bool? {
        if let pid = terminal.processID {
            return ProcessTTY.isRunning(pid, startedAt: terminal.processStartedAt)
        }
        if let tty = terminal.tty {
            return ProcessTTY.hasClaude(on: tty)
        }
        return nil
    }
}
