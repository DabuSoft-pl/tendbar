import AppKit
import SwiftUI
import TendbarKit

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
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var geometry: NotchGeometry?
    private var observer: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
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
        guard let model, model.preferences.notchView, let geometry = NotchGeometry.current() else {
            close()
            return
        }
        if panel == nil || geometry != self.geometry {
            close()
            panel = makePanel(geometry: geometry, model: model)
            self.geometry = geometry
        }
        panel?.orderFrontRegardless()
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        geometry = nil
    }

    private func makePanel(geometry: NotchGeometry, model: AppModel) -> NSPanel {
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
            model: model,
            notchWidth: geometry.notchWidth,
            notchHeight: geometry.notchHeight
        ))
        view.sizingOptions = []
        panel.contentView = view
        panel.setFrame(geometry.panelFrame, display: false)
        return panel
    }
}

private struct NotchView: View {
    let model: AppModel
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    @State private var expanded = false

    private let wing: CGFloat = 44
    private let expandedWidth: CGFloat = 380
    private let radius: CGFloat = 14

    private var active: [Session] {
        model.sessions.filter { $0.state == .working || $0.state == .needsYou || $0.state == .failed || $0.unread }
    }

    private var lead: SessionState? {
        let states = Set(active.map(\.state))
        for state in [SessionState.needsYou, .failed, .working, .done] where states.contains(state) { return state }
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

    var body: some View {
        VStack(spacing: 0) {
            if let lead {
                pill(lead: lead)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.3, bounce: 0.15), value: expanded)
        .animation(.easeInOut(duration: 0.25), value: lead)
    }

    private func pill(lead: SessionState) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "bird.fill")
                    .foregroundStyle(lead.color)
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

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(active.prefix(6)) { session in
                        NotchRow(session: session)
                            .onTapGesture {
                                expanded = false
                                model.select(session)
                            }
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
    }
}

private struct NotchRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(session.state.color).frame(width: 8, height: 8)
            Text(session.folderName).fontWeight(.semibold).lineLimit(1)
            Text(session.state.label).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if session.unread {
                Circle().fill(.blue).frame(width: 6, height: 6)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
