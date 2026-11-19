import SwiftUI
import TendbarApplication
import TendbarDomain

struct NotchView: View {
    let sessions: SessionsViewModel
    let usage: UsageViewModel
    let claudeCode: ClaudeCodeViewModel
    let preferences: Preferences
    let onSelect: (Session) -> Void
    let onAnswer: (PermissionAsk, PermissionDecision) -> Void
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hover: NotchHover

    private var expanded: Bool {
        get { hover.expanded }
        nonmutating set { hover.expanded = newValue }
    }

    init(
        hover: NotchHover,
        sessions: SessionsViewModel,
        usage: UsageViewModel,
        claudeCode: ClaudeCodeViewModel,
        preferences: Preferences,
        onSelect: @escaping (Session) -> Void,
        onAnswer: @escaping (PermissionAsk, PermissionDecision) -> Void = { _, _ in },
        notchWidth: CGFloat,
        notchHeight: CGFloat
    ) {
        self.sessions = sessions
        self.usage = usage
        self.claudeCode = claudeCode
        self.preferences = preferences
        self.onSelect = onSelect
        self.onAnswer = onAnswer
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.hover = hover
    }

    private let wing: CGFloat = 44
    private let closedWing: CGFloat = 26
    private let expandedWidth: CGFloat = 380
    private let radius: CGFloat = 14

    private var active: [Session] {
        sessions.active
    }

    private var lead: SessionState? {
        let states = Set(active.map(\.state))
        for state in [SessionState.needsYou, .working, .failed, .done] where states.contains(state) { return state }
        return nil
    }

    /// The count always belongs to the bird's state, so the pill says one thing at a time.
    private var badge: (count: Int, state: SessionState)? {
        guard let lead else { return nil }
        let count = active.filter { $0.state == lead }.count
        return count > 0 ? (count, lead) : nil
    }

    /// The worst hook state of any profile that needs Connect: sessions may stop arriving, so the pill shows it in
    /// every visibility setting and keeps it until the hooks are connected again.
    private var hookProblem: HookConnection? {
        HookAttention.worst(of: claudeCode.needsConnect)
    }

    private var highestLimit: Double {
        usage.currentLimit
    }

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                pill(lead: lead)
            } else {
                closed(lead: lead)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.25), value: expanded)
        .animation(.easeInOut(duration: 0.25), value: lead)
    }

    @ViewBuilder private func mark(lead: SessionState?) -> some View {
        if let lead {
            TendbarMark(filled: true, height: 14)
                .foregroundStyle(lead.color)
                .modifier(Breathing(active: lead == .working))
        } else {
            TendbarMark(filled: false, height: 14).foregroundStyle(highestLimit >= 70 ? limitColor(highestLimit) : .secondary)
        }
    }

    /// The hook warning, or the count of sessions in the bird's state.
    @ViewBuilder private var status: some View {
        if let hookProblem {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(hookProblem == .helperGone ? Palette.vermilion : Palette.amber)
                .accessibilityLabel(Text("Tendbar's hooks need a click on Connect"))
                .help(Text("Tendbar's hooks need a click on Connect"))
        } else if let badge {
            Text("\(badge.count)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(badge.state.color)
        }
    }

    /// Closed, only a wing left of the notch shows the bird, so the pill is visibly alive. The right side, where the
    /// status items stand, stays free; the app menus on the left rarely reach the notch.
    private func closed(lead: SessionState?) -> some View {
        HStack(spacing: 0) {
            Group {
                if let hookProblem {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(hookProblem == .helperGone ? Palette.vermilion : Palette.amber)
                } else if let lead {
                    TendbarMark(filled: true, height: 11)
                        .foregroundStyle(lead.color)
                        .modifier(Breathing(active: lead == .working))
                } else {
                    TendbarMark(filled: false, height: 11)
                        .foregroundStyle(highestLimit >= 70 ? limitColor(highestLimit) : .secondary)
                }
            }
            .frame(width: closedWing, height: notchHeight)
            // The black runs on under the notch to the screen's middle: the measured notch edge sits a few points
            // off the real one, which left a gap between the wing and the notch.
            .frame(width: closedWing + notchWidth / 2, alignment: .leading)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 9).fill(.black))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { hover.pill = $0 }
            // Empty room as wide as the left side keeps the middle of this row on the notch's middle.
            Color.clear.frame(width: notchWidth / 2 + closedWing, height: notchHeight)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(lead: lead))
    }

    private func pill(lead: SessionState?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                mark(lead: lead).frame(width: wing)
                Spacer(minLength: max(notchWidth, 4))
                status.frame(width: wing)
            }
            .frame(height: notchHeight)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(active.prefix(6)) { session in
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                expanded = false
                                hover.closedByClick = true
                                onSelect(session)
                            } label: {
                                NotchRow(session: session)
                            }
                            .buttonStyle(.plain)
                            if let ask = sessions.ask(for: session) {
                                PermissionPrompt(ask: ask, lineLimit: 3) { onAnswer(ask, $0) }
                                    .id(ask.id)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                                    .padding(.leading, 24)
                                    .padding([.trailing, .bottom], 8)
                            }
                        }
                    }
                    let accounts = usage.accounts
                    if !accounts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(accounts) { account in
                                CompactLimits(account: account, active: usage.isCurrent(account), barWidth: 50)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                            }
                        }
                        .padding(.top, active.isEmpty ? 0 : 8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .frame(width: expandedWidth)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
                .fill(.black)
        )
        // Opening and closing, the content shows only inside the growing shape, not around it.
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
        .contentShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { hover.pill = $0 }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText(lead: lead))
    }

    private func accessibilityText(lead: SessionState?) -> String {
        var parts: [String] = []
        if let lead { parts.append(lead.label) }
        if let badge { parts.append(String(localized: "\(badge.count) sessions: \(badge.state.label)")) }
        if highestLimit > 0 { parts.append(String(localized: "current account limit \(Int(highestLimit.rounded()))%")) }
        return parts.joined(separator: ", ")
    }
}

private struct Breathing: ViewModifier {
    let active: Bool
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(active && dim && !reduceMotion ? 0.45 : 1)
            .onAppear { update() }
            .onChange(of: active) { update() }
    }

    private func update() {
        guard active, !reduceMotion else {
            dim = false
            return
        }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { dim = true }
    }
}

private struct NotchRow: View {
    let session: Session
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            StateMark(state: session.state, unread: session.unread)
            Text(session.displayName).fontWeight(.medium).lineLimit(1)
            Text(session.state.label).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            Spacer()
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(session.timeText(now: context.date))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(Color.white.opacity(hovered ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovered = $0 }
    }
}
