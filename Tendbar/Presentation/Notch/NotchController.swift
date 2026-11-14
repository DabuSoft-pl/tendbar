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
    private let hover = NotchHover()
    private var poll: Timer?

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

    private func checkMouse() {
        guard let panel, panel.isVisible, let geometry else {
            if hover.expanded { hover.expanded = false }
            return
        }
        // A hidden pill still opens from the notch itself, where nothing else can be clicked. Not from the menu bar
        // beside it, whose items it would cover, and not at all on Macs without a notch.
        let notch = CGRect(
            x: (NotchGeometry.panelWidth - geometry.notchWidth) / 2, y: 0, width: geometry.notchWidth, height: geometry.notchHeight
        )
        guard let pill = hover.pill ?? (geometry.hasNotch ? notch : nil) else {
            if hover.expanded { hover.expanded = false }
            return
        }
        let mouse = NSEvent.mouseLocation
        // The pill in screen coordinates; SwiftUI measures from the panel's top left corner.
        let frame = panel.frame
        var area = CGRect(x: frame.minX + pill.minX, y: frame.maxY - pill.maxY, width: pill.width, height: pill.height)
        // Reaching the top edge of the screen still counts, and a little slack keeps an open pill from flickering.
        area = area.insetBy(dx: hover.expanded ? -4 : 0, dy: hover.expanded ? -4 : 0)
        area.size.height = frame.maxY + 1 - area.minY
        let inside = area.contains(mouse)
        if !inside { hover.closedByClick = false }
        let expanded = inside && !hover.closedByClick
        if expanded != hover.expanded { hover.expanded = expanded }
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
        panel?.sharingType = preferences.hideFromCapture ? .none : .readOnly
        panel?.orderFrontRegardless()
        startPolling()
    }

    /// SwiftUI's hover misses an entry in a panel that is never key, and when the pill appears or changes width
    /// under a still cursor. Event monitors for mouse moves broke clicks in the menu bar panel, so the pointer is
    /// polled instead, only while the panel is on screen.
    private func startPolling() {
        guard poll == nil else { return }
        let poll = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMouse() }
        }
        poll.tolerance = 0.05
        RunLoop.main.add(poll, forMode: .common)
        self.poll = poll
    }

    private func close() {
        poll?.invalidate()
        poll = nil
        hover.expanded = false
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
        hover.expanded = false
        let view = FirstClickHostingView(rootView: NotchView(
            hover: hover,
            sessions: sessions,
            usage: usage,
            preferences: preferences,
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

/// The panel never becomes key, so without this AppKit spends the first click on the window and a button in it
/// never fires.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Whether the pointer is over the pill, which the controller works out from mouse moves.
@MainActor
@Observable
final class NotchHover {
    var expanded: Bool
    /// Where the pill sits in its panel, top left origin; nil while it is hidden.
    @ObservationIgnored var pill: CGRect?
    /// A click on a session closes the pill until the pointer leaves it.
    @ObservationIgnored var closedByClick = false

    init(expanded: Bool = false) {
        self.expanded = expanded
    }
}

struct NotchView: View {
    let sessions: SessionsViewModel
    let usage: UsageViewModel
    let preferences: Preferences
    let onSelect: (Session) -> Void
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
        preferences: Preferences,
        onSelect: @escaping (Session) -> Void,
        notchWidth: CGFloat,
        notchHeight: CGFloat
    ) {
        self.sessions = sessions
        self.usage = usage
        self.preferences = preferences
        self.onSelect = onSelect
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.hover = hover
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

    /// The count always belongs to the bird's state, so the pill says one thing at a time.
    private var badge: (count: Int, state: SessionState)? {
        guard let lead else { return nil }
        let count = active.filter { $0.state == lead }.count
        return count > 0 ? (count, lead) : nil
    }

    private var showsPill: Bool {
        switch preferences.pillVisibility {
        case .always: true
        case .activity: lead != nil || highestLimit >= 80
        case .needsYou: lead == .needsYou
        }
    }

    private var highestLimit: Double {
        usage.currentLimit
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsPill || expanded {
                pill(lead: lead)
                    .onDisappear { hover.pill = nil }
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
                        TendbarMark(filled: true, height: 14)
                            .foregroundStyle(lead.color)
                            .modifier(Breathing(active: lead == .working))
                    } else {
                        TendbarMark(filled: false, height: 14).foregroundStyle(highestLimit >= 70 ? limitColor(highestLimit) : .secondary)
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

            if !expanded, highestLimit > 0, preferences.pillLimitLines {
                VStack(spacing: 2) {
                    LimitLine(percentage: usage.currentFiveHour ?? 0)
                    LimitLine(percentage: usage.currentSevenDay ?? 0)
                }
                .padding(.horizontal, radius)
                .padding(.top, 2)
                .padding(.bottom, 6)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(active.prefix(6)) { session in
                        Button {
                            expanded = false
                            hover.closedByClick = true
                            onSelect(session)
                        } label: {
                            NotchRow(session: session)
                        }
                        .buttonStyle(.plain)
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
        .frame(width: expanded ? expandedWidth : max(notchWidth, 4) + wing * 2)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
                .fill(.black)
        )
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
