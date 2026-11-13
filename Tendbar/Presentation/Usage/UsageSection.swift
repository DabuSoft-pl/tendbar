import SwiftUI
import TendbarDomain

struct UsageSection: View {
    let model: UsageViewModel
    let actions: UsageController

    var body: some View {
        let accounts = model.accounts
        if !accounts.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(accounts) { account in
                    AccountLimits(name: account.displayName, account: account, active: model.isCurrent(account))
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Zapomnij to konto") { actions.forget(account) }
                        }
                }
            }
            .font(.callout)
        }
    }
}

private struct AccountLimits: View {
    let name: String
    let account: AccountUsage
    let active: Bool

    var body: some View {
        let now = Date()
        let windows: [(title: String, window: LimitWindow?)] = [
            (String(localized: "5 godz."), account.fiveHour),
            (String(localized: "tydzień"), account.sevenDay),
        ]
        let sorted = windows.sorted { ($0.window?.percentage(at: now) ?? -1) > ($1.window?.percentage(at: now) ?? -1) }
        let lead = sorted[0]
        let rest = sorted[1]

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                if active {
                    Text("aktywne")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                Spacer()
                Text("odczyt \(account.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let window = lead.window {
                let percentage = window.percentage(at: now)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(percentage.rounded()))%")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(percentage >= 70 ? limitColor(percentage) : .primary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(lead.title).foregroundStyle(.secondary)
                        Text(resetText(window, now: now)).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                ProgressView(value: percentage, total: 100)
                    .tint(limitColor(percentage))
                    .accessibilityLabel(lead.title)
                    .accessibilityValue("\(Int(percentage.rounded()))%")
            } else {
                Text("brak danych").foregroundStyle(.tertiary)
            }
            if let window = rest.window {
                let percentage = window.percentage(at: now)
                HStack(spacing: 8) {
                    Text(rest.title).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(percentage.rounded()))%").monospacedDigit()
                    Text(resetText(window, now: now)).foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
        }
    }

    private func resetText(_ window: LimitWindow, now: Date) -> String {
        if now >= window.resetsAt { return String(localized: "zresetowany") }
        return String(localized: "reset \(window.resetsAt.formatted(.relative(presentation: .named)))")
    }
}
