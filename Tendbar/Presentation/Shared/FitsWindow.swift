import AppKit
import SwiftUI

extension View {
    /// Keeps the hosting window as tall as the content. A `MenuBarExtra` window grows with its content but never
    /// shrinks, so folding a section would leave the panel floating in an empty frame.
    func fitsWindow() -> some View {
        modifier(FitsWindow())
    }
}

private struct FitsWindow: ViewModifier {
    @State private var window: NSWindow?
    @State private var lastSize: CGSize?

    func body(content: Content) -> some View {
        content
            .background(WindowReader(window: $window))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                lastSize = size
                fit(to: size)
            }
            .onChange(of: window) { if let lastSize { fit(to: lastSize) } }
    }

    private func fit(to size: CGSize) {
        guard let window, size.height > 0 else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        guard abs(content.height - size.height) > 0.5 else { return }
        var frame = window.frame
        let height = window.frameRect(forContentRect: NSRect(origin: .zero, size: CGSize(width: content.width, height: size.height))).height
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true)
    }
}

private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.onWindow = { window = $0 }
        return view
    }

    func updateNSView(_ view: WindowView, context: Context) {}

    final class WindowView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = window
            DispatchQueue.main.async { [onWindow] in onWindow?(window) }
        }
    }
}
