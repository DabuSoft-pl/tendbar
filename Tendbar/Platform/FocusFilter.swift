import AppIntents
import Foundation

/// Tendbar's Focus filter: System Settings → Focus → a Focus → Add Filter → Tendbar. While that Focus is on, banners
/// follow it in Notification Center as usual, and Tendbar drops what it does by itself: its sounds and the glow.
/// macOS calls `perform()` when the Focus turns on and again, with the defaults, when it turns off.
struct FocusFilter: SetFocusFilterIntent {
    /// Read through `Preferences.alertSettings` each time an alert is about to go out.
    static let quietKey = "focus.quiet"

    static let title: LocalizedStringResource = "Quiet Tendbar"
    static let description: IntentDescription? = IntentDescription("Turn off Tendbar's sounds and screen glow while this Focus is on. Banners follow the Focus as usual.")

    @Parameter(title: "Turn off sounds and glow", default: false)
    var quiet: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: quiet ? "Sounds and glow off" : "Sounds and glow on")
    }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(quiet, forKey: Self.quietKey)
        return .result()
    }
}
