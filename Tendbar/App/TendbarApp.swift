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
            MenuBarLabel(
                sessions: container.sessions,
                usage: container.usage,
                claudeCode: container.claudeCode,
                preferences: container.preferences,
                statusMenu: container.statusMenu
            )
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
    let claudeCode: ClaudeCodeViewModel
    let preferences: Preferences
    let statusMenu: StatusItemMenu
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        label.onAppear { [openSettings] in
            statusMenu.openSettings = { SettingsWindow.open(with: openSettings) }
        }
    }

    @ViewBuilder
    private var label: some View {
        let limit = Int(usage.currentLimit.rounded())
        let waiting = sessions.needsYouCount
        let failed = sessions.sessions.filter { $0.state == .failed && $0.unread }.count
        let bird = waiting > 0 || failed > 0
        if !claudeCode.needsConnect.isEmpty {
            StatusImage(filled: true, label: String(localized: "Tendbar's hooks need a click on Connect"), trailingSymbol: "exclamationmark.triangle")
        } else {
            styled(bird: bird, waiting: waiting, failed: failed, limit: limit)
        }
    }

    @ViewBuilder
    private func styled(bird: Bool, waiting: Int, failed: Int, limit: Int) -> some View {
        switch preferences.menuBarStyle {
        case .bird:
            StatusImage(filled: bird, label: summary(waiting: waiting, failed: failed))
        case .waiting:
            if waiting > 0 {
                StatusImage(filled: bird, label: String(localized: "\(waiting) waiting"), text: "\(waiting)")
            } else if failed > 0 {
                StatusImage(filled: bird, label: String(localized: "\(failed) with an error"), trailingSymbol: "exclamationmark")
            } else if limit >= 90 {
                StatusImage(filled: bird, label: String(localized: "\(limit)% of the limit used"), text: "\(limit)%")
            } else {
                StatusImage(filled: bird, label: "Tendbar")
            }
        case .limit:
            if usage.isEmpty {
                StatusImage(filled: bird, label: summary(waiting: waiting, failed: failed))
            } else {
                StatusImage(filled: bird, label: String(localized: "\(limit)% of the limit used"), text: "\(limit)%")
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
    let filled: Bool
    /// Already localized: says what the figure counts, which the picture alone does not.
    let label: String
    var text: String?
    var trailingSymbol: String?
    /// The scale of the screen the menu bar item is on; a change draws the image again.
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Image(nsImage: rendered)
            .accessibilityLabel(Text(verbatim: label))
    }

    @MainActor
    private var rendered: NSImage {
        let content = HStack(spacing: 3) {
            TendbarMark(filled: filled)
            if let trailingSymbol { Image(systemName: trailingSymbol) }
            if let text { Text(text).monospacedDigit() }
        }
        .font(.system(size: 13))
        .foregroundStyle(.black)
        .fixedSize()
        let renderer = ImageRenderer(content: content)
        renderer.scale = displayScale
        let image = renderer.nsImage ?? TendbarMark.image(filled: filled)
        image.isTemplate = true
        return image
    }
}
