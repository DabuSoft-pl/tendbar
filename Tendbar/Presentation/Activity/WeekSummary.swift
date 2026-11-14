import Charts
import SwiftUI
import TendbarDomain

/// Seven bars, one per day: the time Claude worked, with the time it waited for you stacked on top in the
/// "needs you" color, and the week's totals under them.
struct WeekSummary: View {
    let days: [DatedActivity]

    private var total: DayActivity {
        days.reduce(into: DayActivity()) { $0.add($1.activity) }
    }

    private static let worked = String(localized: "Claude worked")
    private static let waited = String(localized: "Waited for you")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(days) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Hours", item.activity.workSeconds / 3600)
                )
                .foregroundStyle(by: .value("Kind", Self.worked))
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Hours", item.activity.waitSeconds / 3600)
                )
                .foregroundStyle(by: .value("Kind", Self.waited))
            }
            .chartForegroundStyleScale([Self.worked: Color.secondary, Self.waited: Palette.amber])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .chartYAxis(.hidden)
            .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
            .frame(height: 96)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Last 7 days"))
            .accessibilityValue(Text(verbatim: spokenDays))
            TodayLine(title: "Last 7 days", day: total)
        }
    }

    /// One phrase per day for VoiceOver, since the bars alone have no figures.
    private var spokenDays: String {
        days.map { item in
            let weekday = item.day.formatted(.dateTime.weekday(.wide))
            let worked = Elapsed.text(item.activity.workSeconds)
            let waited = Elapsed.text(item.activity.waitSeconds)
            return item.activity.isEmpty
                ? String(localized: "\(weekday): nothing")
                : String(localized: "\(weekday): worked \(worked), waited for you \(waited)")
        }
        .joined(separator: "; ")
    }
}
