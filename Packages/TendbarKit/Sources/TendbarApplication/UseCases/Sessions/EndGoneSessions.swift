import Foundation
import TendbarDomain

/// Runs on a timer: a session whose Claude Code process is gone ends, even when no SessionEnd came, as when its
/// terminal tab was closed or the process was killed.
@MainActor
public final class EndGoneSessions {
    private let repository: SessionRepository
    private let output: SessionsOutput
    private let processes: SessionProcessChecking
    private let desk: PermissionDesk?
    private let clock: Clock

    public init(
        repository: SessionRepository,
        output: SessionsOutput,
        processes: SessionProcessChecking,
        desk: PermissionDesk? = nil,
        clock: Clock
    ) {
        self.repository = repository
        self.output = output
        self.processes = processes
        self.desk = desk
        self.clock = clock
    }

    public func execute() {
        var store = repository.load()
        let gone = store.sessions.values.filter { $0.state != .ended && processes.isRunning($0.terminal) == false }
        guard !gone.isEmpty else { return }
        let now = clock.now()
        for session in gone {
            store.markEnded(session.id, at: now)
            desk?.release(sessionID: session.id)
        }
        repository.save(store)
        output.show(store)
    }
}
