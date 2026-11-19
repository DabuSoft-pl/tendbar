import AppKit
import SwiftUI

@MainActor
final class NotchController {
    private let sessions: SessionsViewModel
    private let sessionActions: SessionsController
    private let usage: UsageViewModel
    private let claudeCode: ClaudeCodeViewModel
    private let preferences: Preferences
    private var panel: NSPanel?
    private var geometry: NotchGeometry?
    private var observer: NSObjectProtocol?
    private let hover = NotchHover()
    private var poll: Timer?

    init(
        sessions: SessionsViewModel,
        sessionActions: SessionsController,
        usage: UsageViewModel,
        claudeCode: ClaudeCodeViewModel,
        preferences: Preferences
    ) {
        self.sessions = sessions
        self.sessionActions = sessionActions
        self.usage = usage
        self.claudeCode = claudeCode
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
        // The closed pill opens from its wing and from the notch itself, where nothing else can be clicked; not from
        // the menu bar right of the notch, whose items the open pill would cover.
        let notch = CGRect(
            x: (NotchGeometry.panelWidth - geometry.notchWidth) / 2, y: 0, width: geometry.notchWidth, height: geometry.notchHeight
        )
        // The open pill covers the notch too, so the union also holds in the frame before it reports its size.
        guard let pill = geometry.hasNotch ? hover.pill?.union(notch) : hover.pill else {
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
        let openedByAsk = followAsks(inside: inside)
        var expanded = (inside || openedByAsk) && !hover.closedByClick
        #if DEBUG
        // `-demo-pill` keeps the pill open for screenshots.
        if CommandLine.arguments.contains("-demo-pill") { expanded = true }
        #endif
        if expanded != hover.expanded { hover.expanded = expanded }
    }

    /// Opens the pill when a new permission prompt waits for Allow or Deny, unless a Focus asked Tendbar to keep
    /// quiet. Returns whether it should stay open for that prompt.
    private func followAsks(inside: Bool) -> Bool {
        let asks = Set(sessions.asks.values.map(\.id))
        if let fresh = asks.subtracting(hover.seenAsks).first, !UserDefaults.standard.bool(forKey: FocusFilter.quietKey) {
            hover.openedFor = fresh
            hover.pointerVisited = inside
        }
        hover.seenAsks = asks
        guard let opened = hover.openedFor else { return false }
        if inside { hover.pointerVisited = true }
        if !asks.contains(opened) || hover.closedByClick || (hover.pointerVisited && !inside) {
            hover.openedFor = nil
            return false
        }
        return true
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
            claudeCode: claudeCode,
            preferences: preferences,
            onSelect: { [sessionActions] in sessionActions.select($0) },
            onAnswer: { [sessionActions] in sessionActions.answer($0, $1) },
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

