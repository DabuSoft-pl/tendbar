import Foundation
import SwiftUI
import TendbarDomain

// How domain values read and look on screen. Kept out of the domain so it stays free of UI concerns.

extension SessionState {
    var label: String {
        switch self {
        case .idle: String(localized: "idle")
        case .working: String(localized: "working")
        case .needsYou: String(localized: "waiting for you")
        case .done: String(localized: "done")
        case .failed: String(localized: "error")
        case .ended: String(localized: "ended")
        }
    }

    var hint: String {
        switch self {
        case .idle: String(localized: "Waiting for the first prompt")
        case .working: String(localized: "Claude is working…")
        case .needsYou: String(localized: "Claude needs your decision")
        case .done: String(localized: "Reply ready")
        case .failed: String(localized: "The turn ended with an error")
        case .ended: String(localized: "Session closed")
        }
    }

    var color: Color {
        switch self {
        case .idle, .ended: .gray
        case .working: .blue
        case .needsYou: .orange
        case .done: .green
        case .failed: .red
        }
    }
}

extension AlertKind {
    var title: String {
        switch self {
        case .needsYou: String(localized: "Waiting for you")
        case .done: String(localized: "Done")
        case .failed: String(localized: "Error")
        }
    }
}

extension Session {
    /// The banner text for an alert about this session.
    func alertBody(for kind: AlertKind) -> String {
        switch kind {
        case .needsYou, .failed: message ?? state.hint
        case .done: preview ?? ""
        }
    }
}

extension AccountUsage {
    var displayName: String {
        email
            ?? configDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? String(localized: "Default account")
    }
}

enum LimitWindowName {
    static func of(_ window: String) -> String {
        switch window {
        case LimitWarnings.fiveHour: String(localized: "5-hour")
        case LimitWarnings.sevenDay: String(localized: "weekly")
        default: window
        }
    }
}

func limitColor(_ percentage: Double) -> Color {
    switch percentage {
    case ..<70: .blue
    case ..<90: .orange
    default: .red
    }
}

/// A limit bar in the limit's color. ProgressView loses its tint in windows that are not key, such as the notch.
struct LimitBar: View {
    let percentage: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(limitColor(percentage))
                    .frame(width: proxy.size.width * min(max(percentage, 0), 100) / 100)
            }
        }
        .frame(height: height)
    }
}
