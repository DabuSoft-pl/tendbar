import SwiftUI
import TendbarDomain

/// One quiet line about today: finished turns, Claude's working time and how long it waited for you.
/// The longest wait and turn sit in the tooltip.
struct TodayLine: View {
    let day: DayActivity

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Today").foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(figures)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.callout)
        .help(details)
        .accessibilityElement(children: .combine)
    }

    private var figures: String {
        var parts = [String(localized: "\(day.turns) turns")]
        if day.workSeconds >= 60 { parts.append(String(localized: "worked \(Elapsed.text(day.workSeconds))")) }
        if day.waitSeconds >= 60 { parts.append(String(localized: "waited for you \(Elapsed.text(day.waitSeconds))")) }
        return parts.joined(separator: " · ")
    }

    private var details: String {
        var lines: [String] = []
        if day.longestTurn >= 60, let folder = day.longestTurnFolder {
            lines.append(String(localized: "Longest turn: \(Elapsed.text(day.longestTurn)) in \(folder)"))
        }
        if day.longestWait >= 60, let folder = day.longestWaitFolder {
            lines.append(String(localized: "Longest wait for you: \(Elapsed.text(day.longestWait)) in \(folder)"))
        }
        return lines.joined(separator: "\n")
    }
}
