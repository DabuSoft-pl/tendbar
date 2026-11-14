import AppKit
import SwiftUI

@main
struct TendbarApp: App {
    @State private var container: AppContainer

    init() {
        #if DEBUG
        Screenshots.runIfRequested()
        #endif
        _container = State(initialValue: AppContainer.live())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(container: container)
        } label: {
            MenuBarLabel(sessions: container.sessions, usage: container.usage, preferences: container.preferences)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(container: container)
        }
    }
}

private struct MenuBarLabel: View {
    let sessions: SessionsViewModel
    let usage: UsageViewModel
    let preferences: Preferences

    var body: some View {
        let limit = Int(usage.currentLimit.rounded())
        let waiting = sessions.needsYouCount
        let failed = sessions.sessions.filter { $0.state == .failed && $0.unread }.count
        let bird = waiting > 0 || failed > 0 ? "bird.fill" : "bird"
        switch preferences.menuBarStyle {
        case .bird:
            StatusImage(symbol: bird, label: summary(waiting: waiting, failed: failed))
        case .waiting:
            if waiting > 0 {
                StatusImage(symbol: bird, label: String(localized: "\(waiting) waiting"), text: "\(waiting)")
            } else if failed > 0 {
                StatusImage(symbol: bird, label: String(localized: "\(failed) with an error"), trailingSymbol: "exclamationmark")
            } else if limit >= 90 {
                StatusImage(symbol: bird, label: String(localized: "\(limit)% of the limit used"), text: "\(limit)%")
            } else {
                StatusImage(symbol: bird, label: "Tendbar")
            }
        case .limit:
            if usage.isEmpty {
                StatusImage(symbol: bird, label: summary(waiting: waiting, failed: failed))
            } else {
                StatusImage(symbol: bird, label: String(localized: "\(limit)% of the limit used"), text: "\(limit)%")
            }
        }
    }

    /// What the filled bird stands for, for VoiceOver.
    private func summary(waiting: Int, failed: Int) -> String {
        if waiting > 0 { return String(localized: "\(waiting) waiting") }
        if failed > 0 { return String(localized: "\(failed) with an error") }
        return "Tendbar"
    }
}

/// The bird and its figure drawn into one template image. A symbol interpolated into `Text` can drop out of the
/// status item and leave the figure alone, so the menu bar gets a single picture it always shows whole.
private struct StatusImage: View {
    let symbol: String
    /// Already localized: says what the figure counts, which the picture alone does not.
    let label: String
    var text: String?
    var trailingSymbol: String?

    var body: some View {
        Image(nsImage: rendered)
            .accessibilityLabel(Text(verbatim: label))
    }

    @MainActor
    private var rendered: NSImage {
        let content = HStack(spacing: 3) {
            Image(systemName: symbol)
            if let trailingSymbol { Image(systemName: trailingSymbol) }
            if let text { Text(text).monospacedDigit() }
        }
        .font(.system(size: 13))
        .foregroundStyle(.black)
        .fixedSize()
        let renderer = ImageRenderer(content: content)
        // The sharpest screen, not the main one: the menu bar may sit on a Retina display while another screen is
        // main, and the image is not drawn again when screens change.
        renderer.scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        return image
    }
}
