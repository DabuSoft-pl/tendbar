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
}
