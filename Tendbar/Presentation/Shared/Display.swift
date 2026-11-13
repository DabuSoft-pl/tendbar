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

    /// Color is kept for what asks for you. A working session is the neutral ink of the text around it.
    var color: Color {
        switch self {
        case .idle, .ended: .gray
        case .working: .primary
        case .needsYou: Palette.amber
        case .done: Palette.sage
        case .failed: Palette.vermilion
        }
    }
}

/// Tendbar's own colors, taken from the app icon: an amber bird on a cream perch.
enum Palette {
    static let amber = Color(red: 1.0, green: 0.60, blue: 0.12)
    static let sage = Color(red: 0.49, green: 0.72, blue: 0.58)
    static let vermilion = Color(red: 0.89, green: 0.34, blue: 0.24)
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
    /// How long a working session has been at it, or how long ago anything else last changed.
    func timeText(now: Date = Date()) -> String {
        if state == .working {
            return String(localized: "for \(Elapsed.text(now.timeIntervalSince(turnStartedAt ?? updatedAt)))")
        }
        return Elapsed.ago(updatedAt, now: now)
    }

    /// The line under the folder name: the kind, and for a finished turn how long it took.
    func alertSubtitle(for kind: AlertKind) -> String {
        guard kind == .done, let start = turnStartedAt, updatedAt.timeIntervalSince(start) >= 60 else { return kind.title }
        return String(localized: "Done after \(Elapsed.text(updatedAt.timeIntervalSince(start)))")
    }

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

    /// The part of the e-mail address before the @, for rows too narrow for the whole address.
    var shortName: String {
        guard let email, let at = email.firstIndex(of: "@"), at > email.startIndex else { return displayName }
        return String(email[..<at])
    }
}

/// One way to write a stretch of time across the app: a single unit, abbreviated, such as "6 min", "2 hr" or "3 days".
enum Elapsed {
    static func text(_ interval: TimeInterval) -> String {
        let seconds = max(interval, 60)
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 1)
        )
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return String(localized: "now") }
        return String(localized: "\(text(now.timeIntervalSince(date))) ago")
    }

    static func until(_ date: Date, now: Date = Date()) -> String {
        text(date.timeIntervalSince(now))
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
    case ..<70: .primary.opacity(0.55)
    case ..<90: Palette.amber
    default: Palette.vermilion
    }
}

/// A limit bar in the limit's color. ProgressView loses its tint in windows that are not key, such as the notch.
/// The optional tick marks the even pace: usage past it is ahead of the window.
struct LimitBar: View {
    let percentage: Double
    var height: CGFloat = 6
    var pace: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(limitColor(percentage))
                    .frame(width: proxy.size.width * min(max(percentage, 0), 100) / 100)
                if let pace {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.85))
                        .frame(width: 2, height: height + 4)
                        .offset(x: min(max(proxy.size.width * pace / 100 - 1, 0), proxy.size.width - 2))
                }
            }
        }
        .frame(height: height)
    }
}
