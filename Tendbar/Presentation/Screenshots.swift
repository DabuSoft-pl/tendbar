#if DEBUG
import AppKit
import SwiftUI

/// `Tendbar -screenshots <folder>` (Debug builds) renders the README images from sample data and quits.
/// `-screenshots-extra` adds the other settings pages and an empty panel, for checking the layout.
@MainActor
enum Screenshots {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-screenshots"), arguments.indices.contains(index + 1) else { return }
        let folder = URL(fileURLWithPath: arguments[index + 1])
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let container = PreviewData.container()
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            render(panel(container), size: CGSize(width: 400, height: 640), appearance: appearance, to: folder.appendingPathComponent("panel-\(name).png"))
            renderWindow(SettingsView(container: container), appearance: appearance, to: folder.appendingPathComponent("settings-\(name).png"))
        }
        if arguments.contains("-screenshots-extra") {
            for page in SettingsPage.allCases where page != .claudeCode {
                renderWindow(SettingsView(container: container, page: page), appearance: .darkAqua, to: folder.appendingPathComponent("settings-\(page.rawValue).png"))
            }
            let empty = PreviewData.container(sessions: [], accounts: [])
            render(panel(empty), size: CGSize(width: 400, height: 640), appearance: .darkAqua, to: folder.appendingPathComponent("panel-empty.png"))
            let unhooked = PreviewData.container(hooks: [nil: .helperGone, "/Users/me/.claude-work": .otherCopy])
            render(panel(unhooked), size: CGSize(width: 400, height: 640), appearance: .darkAqua, to: folder.appendingPathComponent("panel-hooks.png"))
            render(notch(unhooked, expanded: false), size: CGSize(width: 520, height: 64), appearance: .darkAqua, to: folder.appendingPathComponent("notch-hooks.png"))
        }
        render(notch(container, expanded: true), size: CGSize(width: 520, height: 280), appearance: .darkAqua, to: folder.appendingPathComponent("notch-expanded.png"))
        exit(0)
    }

    private static func panel(_ container: AppContainer) -> some View {
        MenuContent(container: container)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private static func notch(_ container: AppContainer, expanded: Bool) -> some View {
        NotchView(
            hover: NotchHover(expanded: expanded),
            sessions: container.sessions,
            usage: container.usage,
            claudeCode: container.claudeCode,
            preferences: container.preferences,
            onSelect: { _ in },
            notchWidth: 190,
            notchHeight: 32
        )
        .frame(width: 520, height: expanded ? 280 : 64)
        .background(Color(white: 0.16))
    }

    /// A real settings window, title bar and close button included, drawn with a soft shadow on a clear canvas, so
    /// the README shows a window rather than a cut-out.
    private static func renderWindow(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let size = CGSize(width: 700, height: 500)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        window.orderOut(nil)

        let margin: CGFloat = 40
        let canvas = NSImage(size: CGSize(width: size.width + margin * 2, height: size.height + margin * 2))
        canvas.lockFocus()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = CGSize(width: 0, height: -8)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        let rect = CGRect(origin: CGPoint(x: margin, y: margin), size: size)
        let outline = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        outline.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(appearance == .darkAqua ? 0.6 : 0.12).setStroke()
        outline.lineWidth = 1
        outline.stroke()
        canvas.unlockFocus()
        guard let data = canvas.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { return }
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func render(_ view: some View, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width).fixedSize(horizontal: false, vertical: true))
        host.appearance = NSAppearance(named: appearance)
        let fitting = host.fittingSize
        let frame = CGRect(origin: .zero, size: CGSize(width: size.width, height: max(fitting.height, 10)))
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        host.frame = frame
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

#endif
