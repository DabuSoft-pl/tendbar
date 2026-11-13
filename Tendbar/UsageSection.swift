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
                            Text(model.accountName(account)).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            Text(readingText(account))
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                        LimitRow(title: String(localized: "5 godz."), window: account.fiveHour)
                        LimitRow(title: String(localized: "Tydzień"), window: account.sevenDay)
                        ForEach(account.scoped ?? [], id: \.name) { scoped in
                            LimitRow(title: scoped.name, window: scoped.window)
                        }
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Zapomnij to konto") { model.forget(account) }
                    }
                }
            }
            .font(.callout)
        }
    }

    private func readingText(_ account: AccountUsage) -> String {
        let when = account.updatedAt.formatted(.relative(presentation: .named))
        return account.source == .claudeSwap
            ? String(localized: "cswap, \(when)")
            : String(localized: "odczyt \(when)")
    }
}

private struct LimitRow: View {
    let title: String
    let window: LimitWindow?

    var body: some View {
        let now = Date()
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 56, alignment: .leading)
            if let window {
                let percentage = window.percentage(at: now)
                ProgressView(value: percentage, total: 100)
                    .tint(limitColor(percentage))
                Text("\(Int(percentage.rounded()))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                Text(resetText(window, now: now))
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

    private func resetText(_ window: LimitWindow, now: Date) -> String {
        if window.resetsAt == .distantFuture { return String(localized: "nie rozpoczęty") }
        if now >= window.resetsAt { return String(localized: "zresetowany") }
        return window.resetsAt.formatted(.relative(presentation: .named))
    }
}
