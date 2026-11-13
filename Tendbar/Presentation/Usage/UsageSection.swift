import SwiftUI
import TendbarDomain

struct UsageSection: View {
    let model: UsageViewModel
    let actions: UsageController
    var compact = false

    var body: some View {
        let accounts = model.accounts
        if !accounts.isEmpty {
            VStack(alignment: .leading, spacing: compact ? 8 : 16) {
                ForEach(accounts) { account in
                    Group {
                        if compact {
                            CompactLimits(name: account.displayName, account: account, active: model.isCurrent(account))
                        } else {
                            AccountLimits(name: account.displayName, account: account, active: model.isCurrent(account))
                        }
                    }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Forget this account") { actions.forget(account) }
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
            (String(localized: "5-hour"), account.fiveHour),
            (String(localized: "weekly"), account.sevenDay),
        ]
        let sorted = windows.sorted { ($0.window?.percentage(at: now) ?? -1) > ($1.window?.percentage(at: now) ?? -1) }
        let lead = sorted[0]
        let rest = sorted[1]

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                if active {
                    Text("current")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                Spacer()
                Text("read \(account.updatedAt.formatted(.relative(presentation: .named)))")
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
                LimitBar(percentage: percentage)
                    .accessibilityLabel(lead.title)
                    .accessibilityValue("\(Int(percentage.rounded()))%")
            } else {
                Text("no data").foregroundStyle(.tertiary)
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
        if now >= window.resetsAt { return String(localized: "reset") }
        return String(localized: "resets \(window.resetsAt.formatted(.relative(presentation: .named)))")
    }
}

/// One line per account: the name, then the five-hour and weekly usage as short bars.
private struct CompactLimits: View {
    let name: String
    let account: AccountUsage
    let active: Bool

    var body: some View {
        let now = Date()
        HStack(spacing: 12) {
            Text(name)
                .fontWeight(active ? .medium : .regular)
                .foregroundStyle(active ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            gauge(String(localized: "5h"), account.fiveHour, now: now)
            gauge(String(localized: "7d"), account.sevenDay, now: now)
        }
        .accessibilityElement(children: .combine)
    }

    private func gauge(_ title: String, _ window: LimitWindow?, now: Date) -> some View {
        let percentage = window?.percentage(at: now) ?? 0
        return HStack(spacing: 6) {
            Text(title).foregroundStyle(.tertiary).fixedSize()
            LimitBar(percentage: percentage, height: 4).frame(width: 44)
            Text(window == nil ? "–" : "\(Int(percentage.rounded()))%")
                .monospacedDigit()
                .foregroundStyle(percentage >= 70 ? limitColor(percentage) : .secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
