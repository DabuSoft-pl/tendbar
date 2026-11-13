import Foundation

/// Sessions that need a second look: a wait that went unanswered, or a working session that has gone quiet.
public enum Attention {
    /// Sessions waiting for you for at least `after`, not reminded yet about this wait.
    public static func dueReminders(in store: SessionStore, now: Date, after: TimeInterval) -> [Session] {
        store.ordered.filter { session in
            guard session.state == .needsYou, !session.remindedWait, let since = session.waitingSince else { return false }
            return now.timeIntervalSince(since) >= after
        }
    }

    /// A working session with no hook event for at least `after`. It may be stuck, or running one long command.
    public static func isQuiet(_ session: Session, now: Date, after: TimeInterval) -> Bool {
        session.state == .working && now.timeIntervalSince(session.updatedAt) >= after
    }

    /// Quiet sessions the user has not been told about yet.
    public static func newlyQuiet(in store: SessionStore, now: Date, after: TimeInterval) -> [Session] {
        store.ordered.filter { !$0.flaggedQuiet && isQuiet($0, now: now, after: after) }
    }
}
