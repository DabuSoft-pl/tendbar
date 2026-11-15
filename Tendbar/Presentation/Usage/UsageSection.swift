import SwiftUI
import TendbarDomain

/// The current account in full, with the pace of each window. Other accounts, or every account in the compact
/// style, take one line each.
struct UsageSection: View {
    let model: UsageViewModel
    let actions: UsageController
    var compact = false

    var body: some View {
        let accounts = model.accounts
        if let first = accounts.first {
            VStack(alignment: .leading, spacing: 12) {
                if !compact {
                    AccountLimits(account: first)
                        .modifier(ForgetMenu(account: first, actions: actions))
                }
                let rest = compact ? accounts : Array(accounts.dropFirst())
                if !rest.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rest) { account in
                            CompactLimits(account: account, active: model.isCurrent(account))
                                .modifier(ForgetMenu(account: account, actions: actions))
                        }
                    }
                }
            }
            .font(.callout)
        }
    }
}

private struct ForgetMenu: ViewModifier {
    let account: AccountUsage
    let actions: UsageController

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .contextMenu {
                Button("Forget this account") { actions.forget(account) }
            }
    }
}

private struct AccountLimits: View {
    let account: AccountUsage

    var body: some View {
        // "read … ago", the pace tick and a reset come with time, not with a new reading.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            limits(now: context.date)
        }
    }

    private func limits(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(account.displayName).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("read \(Elapsed.ago(account.updatedAt, now: now))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            WindowLimit(
                title: String(localized: "5-hour"),
                window: account.fiveHour,
                length: LimitWindow.fiveHourLength,
                readAt: account.updatedAt,
                now: now
            )
            WindowLimit(
                title: String(localized: "weekly"),
                window: account.sevenDay,
                length: LimitWindow.sevenDayLength,
                readAt: account.updatedAt,
                now: now
            )
        }
    }
}

/// One window: its share, a bar with a tick at the even pace, when it resets and, if usage runs ahead, when it
/// would run out.
private struct WindowLimit: View {
    let title: String
    let window: LimitWindow?
    let length: TimeInterval
    let readAt: Date
    let now: Date

    var body: some View {
        let percentage = window?.percentage(at: now) ?? 0
        let pace = window?.evenPace(at: now, length: length)
        let runsOut = window?.runsOut(readAt: readAt, now: now, length: length)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(window == nil ? "–" : "\(Int(percentage.rounded()))%")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(percentage >= 70 ? limitColor(percentage) : .primary)
            }
            // The bar and the figure show what is used; a run-out forecast warns only in the line below.
            LimitBar(percentage: percentage, pace: pace)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(percentage.rounded()))%")
            if let window {
                HStack(spacing: 0) {
                    Text(resetText(window, short: runsOut != nil))
                        .foregroundStyle(.secondary)
                    if let runsOut {
                        Text(" · ").foregroundStyle(.tertiary)
                        Text("at this pace out in \(Elapsed.until(runsOut, now: now))")
                            .foregroundStyle(limitColor(max(percentage, 70)))
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }
        }
    }

    /// With a run-out forecast beside it only the clock time fits, so the countdown goes.
    private func resetText(_ window: LimitWindow, short: Bool) -> String {
        if now >= window.resetsAt { return String(localized: "reset") }
        if short { return String(localized: "resets \(Elapsed.clock(window.resetsAt, now: now))") }
        return String(localized: "resets in \(Elapsed.until(window.resetsAt, now: now)), at \(Elapsed.clock(window.resetsAt, now: now))")
    }
}

/// One account in short: the name, the five-hour and weekly usage as short bars and, below, when each resets.
struct CompactLimits: View {
    let account: AccountUsage
    let active: Bool
    var barWidth: CGFloat = 44

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 2) {
                line(now: context.date)
                if let resets = resets(now: context.date) {
                    Text(resets)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Only windows still running: a window past its reset has no next time until a new reading.
    private func resets(now: Date) -> String? {
        var parts: [String] = []
        if let window = account.fiveHour, now < window.resetsAt {
            parts.append(String(localized: "5h resets \(Elapsed.clock(window.resetsAt, now: now))"))
        }
        if let window = account.sevenDay, now < window.resetsAt {
            parts.append(String(localized: "7d resets \(Elapsed.clock(window.resetsAt, now: now))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func line(now: Date) -> some View {
        HStack(spacing: 12) {
            Text(account.shortName)
                .fontWeight(active ? .medium : .regular)
                .foregroundStyle(active ? .primary : .secondary)
                .lineLimit(1)
                .help(account.displayName)
            Spacer(minLength: 8)
            gauge(String(localized: "5h"), account.fiveHour, length: LimitWindow.fiveHourLength, now: now)
            gauge(String(localized: "7d"), account.sevenDay, length: LimitWindow.sevenDayLength, now: now)
        }
    }

    private func gauge(_ title: String, _ window: LimitWindow?, length: TimeInterval, now: Date) -> some View {
        let percentage = window?.percentage(at: now) ?? 0
        return HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary).fixedSize()
            LimitBar(percentage: percentage, height: 4, pace: window?.evenPace(at: now, length: length))
                .frame(width: barWidth)
            Text(window == nil ? "–" : "\(Int(percentage.rounded()))%")
                .monospacedDigit()
                .foregroundStyle(percentage >= 70 ? limitColor(percentage) : .secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
