public enum AlertKind: String, Sendable, CaseIterable {
    case needsYou
    case done
    case failed
    /// A wait that went unanswered for a while.
    case reminder
    /// A working session with no events for a while.
    case quiet
}

public enum AlertPolicy {
    public static func alert(from previous: SessionState?, to current: SessionState) -> AlertKind? {
        guard previous != current else { return nil }
        switch current {
        case .needsYou: return .needsYou
        case .done: return .done
        case .failed: return .failed
        case .idle, .working, .ended: return nil
        }
    }
}
