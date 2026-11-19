import Foundation
import Observation

/// Whether the pointer is over the pill, which the controller works out from mouse moves.
@MainActor
@Observable
final class NotchHover {
    var expanded: Bool
    /// Where the pill (closed: its wing) sits in its panel, top left origin; nil before its first layout.
    @ObservationIgnored var pill: CGRect?
    /// A click on a session closes the pill until the pointer leaves it.
    @ObservationIgnored var closedByClick = false
    /// The permission prompt that opened the pill by itself. It stays open until that prompt is answered anywhere,
    /// a session is clicked, or the pointer has been in the pill and left it.
    @ObservationIgnored var openedFor: String?
    @ObservationIgnored var pointerVisited = false
    /// Prompts already seen, so each one opens the pill once.
    @ObservationIgnored var seenAsks: Set<String> = []

    init(expanded: Bool = false) {
        self.expanded = expanded
    }
}
