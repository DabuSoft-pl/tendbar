import Observation
import TendbarApplication

@MainActor
@Observable
final class ClaudeCodeViewModel {
    /// Nil until checked, and when the app has no hook helper.
    var connection: HookConnection?
    var helperAvailable = true
    var connectionError: String?
    var profiles: [ProfileSummary] = []
    var profileError: String?

    /// Profiles whose hooks need a click on Connect, `~/.claude` first. While any is listed, the menu bar item and the
    /// panel say so: with the hooks of another copy or of a deleted one, sessions stop arriving without a sound.
    var needsConnect: [ProfileSummary] {
        profiles.filter { $0.connection?.needsConnect == true }
    }
}
