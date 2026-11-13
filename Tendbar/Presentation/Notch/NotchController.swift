import AppKit
import SwiftUI
import TendbarDomain

struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    init?(notchOf screen: NSScreen) {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }
        screenFrame = screen.frame
        notchWidth = screen.frame.width - left.width - right.width
        notchHeight = screen.safeAreaInsets.top
    }

    init(menuBarOf screen: NSScreen) {
        screenFrame = screen.frame
        notchWidth = 0
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        notchHeight = menuBar > 0 ? menuBar : 24
    }

    static func current() -> NotchGeometry? {
        if let notch = NSScreen.screens.lazy.compactMap(NotchGeometry.init(notchOf:)).first { return notch }
        return NSScreen.screens.first.map(NotchGeometry.init(menuBarOf:))
    }

    var hasNotch: Bool {
        notchWidth > 0
    }

    static let panelWidth: CGFloat = 420
    static let panelExtraHeight: CGFloat = 360

    var panelFrame: CGRect {
        let height = notchHeight + Self.panelExtraHeight
        return CGRect(
            x: screenFrame.midX - Self.panelWidth / 2,
            y: screenFrame.maxY - height,
            width: Self.panelWidth,
            height: height
        )
    }
}

@MainActor
final class NotchController {
    private let sessions: SessionsViewModel
    private let sessionActions: SessionsController
    private let usage: UsageViewModel
    private let preferences: Preferences
    private var panel: NSPanel?
    private var geometry: NotchGeometry?
    private var observer: NSObjectProtocol?

    init(sessions: SessionsViewModel, sessionActions: SessionsController, usage: UsageViewModel, preferences: Preferences) {
        self.sessions = sessions
        self.sessionActions = sessionActions
        self.usage = usage
        self.preferences = preferences
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
    }

    static var hasNotch: Bool {
        NotchGeometry.current()?.hasNotch == true
    }

    func update() {
        guard preferences.notchView, let geometry = NotchGeometry.current() else {
            close()
            return
        }
        if panel == nil || geometry != self.geometry {
            close()
            panel = makePanel(geometry: geometry)
            self.geometry = geometry
        }
        panel?.orderFrontRegardless()
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        geometry = nil
    }

    private func makePanel(geometry: NotchGeometry) -> NSPanel {
        let panel = NSPanel(
            contentRect: geometry.panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NSHostingView(rootView: NotchView(
            sessions: sessions,
            usage: usage,
            onSelect: { [sessionActions] in sessionActions.select($0) },
            notchWidth: geometry.notchWidth,
            notchHeight: geometry.notchHeight
        ))
        view.sizingOptions = []
        panel.contentView = view
        panel.setFrame(geometry.panelFrame, display: false)
        return panel
    }
}

struct NotchView: View {
    let sessions: SessionsViewModel
    let usage: UsageViewModel
    let onSelect: (Session) -> Void
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    @State private var expanded: Bool

    init(
        sessions: SessionsViewModel,
        usage: UsageViewModel,
        onSelect: @escaping (Session) -> Void,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        expanded: Bool = false
    ) {
        self.sessions = sessions
        self.usage = usage
        self.onSelect = onSelect
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        _expanded = State(initialValue: expanded)
    }

    private let wing: CGFloat = 44
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

    private var badge: (count: Int, state: SessionState)? {
        let needsYou = active.filter { $0.state == .needsYou }.count
        if needsYou > 0 { return (needsYou, .needsYou) }
        let failed = active.filter { $0.state == .failed }.count
        if failed > 0 { return (failed, .failed) }
        let done = active.filter { $0.state == .done && $0.unread }.count
        if done > 0 { return (done, .done) }
        let working = active.filter { $0.state == .working }.count
        return working > 0 ? (working, .working) : nil
    }

    private var highestLimit: Double {
        usage.currentLimit
    }

    var body: some View {
        VStack(spacing: 0) {
            if lead != nil || highestLimit >= 80 {
                pill(lead: lead)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.25), value: expanded)
        .animation(.easeInOut(duration: 0.25), value: lead)
    }

    private func pill(lead: SessionState?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    if let lead {
                        Image(systemName: "bird.fill")
                            .foregroundStyle(lead.color)
                            .modifier(Breathing(active: lead == .working))
                    } else {
                        Image(systemName: "bird").foregroundStyle(limitColor(highestLimit))
                    }
                }
                .frame(width: wing)
                Spacer(minLength: max(notchWidth, 4))
                Group {
                    if let badge {
                        Text("\(badge.count)")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(badge.state.color)
                    }
                }
                .frame(width: wing)
            }
            .frame(height: notchHeight)

            if !expanded, highestLimit > 0 {
                VStack(spacing: 2) {
                    LimitLine(percentage: usage.currentFiveHour ?? 0)
                    LimitLine(percentage: usage.currentSevenDay ?? 0)
                }
                .padding(.horizontal, radius)
                .padding(.top, 2)
                .padding(.bottom, 6)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(active.prefix(6)) { session in
                        NotchRow(session: session)
                            .onTapGesture {
                                expanded = false
                                onSelect(session)
                            }
                    }
                    let accounts = usage.accounts
                    if !accounts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(accounts) { account in
                                NotchLimitRow(
                                    name: account.displayName,
                                    account: account,
                                    active: usage.isCurrent(account)
                                )
                            }
                        }
                        .padding(.top, active.isEmpty ? 0 : 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .frame(width: expanded ? expandedWidth : max(notchWidth, 4) + wing * 2)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
                .fill(.black)
        )
        .contentShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
        .onHover { expanded = $0 }
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

private struct LimitLine: View {
    let percentage: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(limitColor(percentage))
                    .frame(width: proxy.size.width * min(percentage, 100) / 100)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
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

private struct NotchLimitRow: View {
    let name: String
    let account: AccountUsage
    let active: Bool

    var body: some View {
        let now = Date()
        HStack(spacing: 8) {
            Circle()
                .fill(active ? Color.white : Color.clear)
                .strokeBorder(.white.opacity(0.4), lineWidth: active ? 0 : 1)
                .frame(width: 6, height: 6)
                .accessibilityLabel(active ? String(localized: "current account") : String(localized: "other account"))
            Text(name)
                .foregroundStyle(active ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            gauge(String(localized: "5h"), account.fiveHour, now: now)
            gauge(String(localized: "7d"), account.sevenDay, now: now)
        }
        .font(.system(size: 11))
        .foregroundStyle(.white)
        .opacity(active ? 1 : 0.6)
        .padding(.horizontal, 8)
    }

    private func gauge(_ title: String, _ window: LimitWindow?, now: Date) -> some View {
        let percentage = window?.percentage(at: now) ?? 0
        return HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary).fixedSize()
            LimitBar(percentage: percentage, height: 4)
                .frame(width: 50)
            Text(window == nil ? "–" : "\(Int(percentage.rounded()))%")
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }
}

private struct NotchRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            StateMark(state: session.state, unread: session.unread)
            Text(session.folderName).fontWeight(.medium).lineLimit(1)
            Text(session.state.label).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
