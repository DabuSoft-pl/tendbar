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

    /// Profiles whose hooks need a click on Connect, `~/.claude` first.
    var needsConnect: [ProfileSummary] {
        HookAttention.profilesNeedingConnect(profiles)
    }
}
