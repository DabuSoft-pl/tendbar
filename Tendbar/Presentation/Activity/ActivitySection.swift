import SwiftUI
import TendbarDomain

/// The "Today" line, and under it, after a click, the last seven days. Hidden while the week is empty.
struct ActivitySection: View {
    let model: ActivityViewModel
    @AppStorage("panel.showsWeek") private var showsWeek = false

    var body: some View {
        let week = model.week()
        if week.contains(where: { !$0.activity.isEmpty }) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showsWeek.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showsWeek ? 90 : 0))
                        TodayLine(day: week.last?.activity ?? DayActivity())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(showsWeek ? "Hides the last 7 days" : "Shows the last 7 days"))
                if showsWeek {
                    WeekSummary(days: week)
                        .padding(.leading, 16)
                        .transition(.opacity)
                }
            }
        }
    }
}
