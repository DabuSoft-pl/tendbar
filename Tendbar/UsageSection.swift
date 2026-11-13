import SwiftUI
import TendbarKit

struct UsageSection: View {
    let model: AppModel

    var body: some View {
        let accounts = model.usage.ordered
        if !accounts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(accounts) { account in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(model.accountName(account)).fontWeight(.semibold).lineLimit(1)
                            Spacer()
                            Text("odczyt \(account.updatedAt.formatted(.relative(presentation: .named)))")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                        LimitRow(title: "5 godz.", window: account.fiveHour)
                        LimitRow(title: "Tydzień", window: account.sevenDay)
                    }
                }
            }
            .font(.callout)
        }
    }
}

private struct LimitRow: View {
    let title: LocalizedStringKey
    let window: LimitWindow?

    var body: some View {
        let now = Date()
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            if let window {
                let percentage = window.percentage(at: now)
                ProgressView(value: percentage, total: 100)
                    .tint(color(for: percentage))
                Text("\(Int(percentage.rounded())) %")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                Text(now >= window.resetsAt
                    ? String(localized: "zresetowany")
                    : window.resetsAt.formatted(.relative(presentation: .named)))
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .trailing)
                    .lineLimit(1)
            } else {
                Text("brak danych")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    private func color(for percentage: Double) -> Color {
        switch percentage {
        case ..<70: .blue
        case ..<90: .orange
        default: .red
        }
    }
}
