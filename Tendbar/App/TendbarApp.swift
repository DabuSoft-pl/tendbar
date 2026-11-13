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
            StatusImage(symbol: bird)
        case .waiting:
            if waiting > 0 {
                StatusImage(symbol: bird, text: "\(waiting)")
            } else if failed > 0 {
                StatusImage(symbol: bird, trailingSymbol: "exclamationmark")
                    .accessibilityLabel(String(localized: "\(failed) with an error"))
            } else if limit >= 90 {
                StatusImage(symbol: bird, text: "\(limit)%")
            } else {
                StatusImage(symbol: bird)
            }
        case .limit:
            if usage.isEmpty {
                StatusImage(symbol: bird)
            } else {
                StatusImage(symbol: bird, text: "\(limit)%")
            }
        }
    }
}

/// The bird and its figure drawn into one template image. A symbol interpolated into `Text` can drop out of the
/// status item and leave the figure alone, so the menu bar gets a single picture it always shows whole.
private struct StatusImage: View {
    let symbol: String
    var text: String?
    var trailingSymbol: String?

    var body: some View {
        Image(nsImage: rendered)
            .accessibilityLabel(Text(text.map { "Tendbar \($0)" } ?? "Tendbar"))
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
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        return image
    }
}
