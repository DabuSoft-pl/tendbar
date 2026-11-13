import AppKit
import SwiftUI
import TendbarApplication

@MainActor
final class EdgeGlow: ScreenFlashing {
    static let duration: TimeInterval = 2.0

    private var windows: [NSWindow] = []
    private var hideTask: Task<Void, Never>?
    private let hidesFromCapture: () -> Bool

    init(hidesFromCapture: @escaping () -> Bool = { true }) {
        self.hidesFromCapture = hidesFromCapture
    }

    func flash(_ tone: FlashTone) {
        switch tone {
        case .attention: flash(color: Palette.amber)
        case .success: flash(color: Palette.sage)
        case .failure: flash(color: Palette.vermilion)
        }
    }

    private func flash(color: Color) {
        hideTask?.cancel()
        close()
        let calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.sharingType = hidesFromCapture() ? .none : .readOnly
            let radius: CGFloat = screen.safeAreaInsets.top > 0 ? 10 : 0
            window.contentView = NSHostingView(rootView: GlowView(color: color, calm: calm, topRadius: radius))
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            windows.append(window)
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.duration))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    func close() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }
}

private struct GlowView: View {
    let color: Color
    let calm: Bool
    let topRadius: CGFloat
    @State private var opacity = 0.0

    private var edge: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: topRadius, topTrailingRadius: topRadius)
    }

    var body: some View {
        ZStack {
            edge
                .strokeBorder(color, lineWidth: 14)
                .blur(radius: 18)
            edge
                .strokeBorder(color.opacity(0.85), lineWidth: 3)
                .blur(radius: 1)
        }
        .opacity(opacity)
        .ignoresSafeArea()
        .task {
            withAnimation(.easeOut(duration: 0.25)) { opacity = 1 }
            if !calm {
                try? await Task.sleep(for: .seconds(0.45))
                withAnimation(.easeInOut(duration: 0.3)) { opacity = 0.3 }
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation(.easeInOut(duration: 0.3)) { opacity = 1 }
            }
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(.easeIn(duration: 0.4)) { opacity = 0 }
        }
    }
}
