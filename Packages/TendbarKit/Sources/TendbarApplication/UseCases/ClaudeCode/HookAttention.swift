import TendbarDomain

/// Which profiles need a click on Connect, and which of their states to name first. With the hooks of another copy
/// or of a deleted one, sessions stop arriving without a sign, so the menu bar item and the panel say so.
public enum HookAttention {
    /// Profiles whose hooks are not connected to this copy of Tendbar, in the order given (`~/.claude` first).
    public static func profilesNeedingConnect(_ profiles: [ProfileSummary]) -> [ProfileSummary] {
        profiles.filter { $0.connection?.needsConnect == true }
    }

    /// The state that loses the most events: no events at all, then a profile left out, then events through another
    /// copy, then missing events or timeouts.
    public static func worst(of profiles: [ProfileSummary]) -> HookConnection? {
        let order: [HookConnection] = [.helperGone, .disconnected, .otherCopy, .outdated]
        let states = profiles.compactMap(\.connection)
        return order.first(where: states.contains)
    }
}
