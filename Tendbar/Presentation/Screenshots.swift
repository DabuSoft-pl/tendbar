#if DEBUG
import AppKit
import SwiftUI

/// `Tendbar -screenshots <folder>` (Debug builds) renders the README images from sample data and quits.
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
            render(SettingsView(container: container), size: CGSize(width: 700, height: 500), appearance: appearance, to: folder.appendingPathComponent("settings-\(name).png"))
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
            sessions: container.sessions,
            usage: container.usage,
            preferences: container.preferences,
            onSelect: { _ in },
            notchWidth: 190,
            notchHeight: 32,
            expanded: expanded
        )
        .frame(width: 520, height: expanded ? 280 : 64)
        .background(Color(white: 0.16))
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
