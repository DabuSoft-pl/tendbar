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
        let bird = Image(systemName: waiting > 0 ? "bird.fill" : "bird")
        switch preferences.menuBarStyle {
        case .bird:
            bird
        case .waiting:
            if waiting > 0 {
                Text("\(bird) \(waiting)")
            } else if limit >= 90 {
                Text("\(bird) \(limit)%")
            } else {
                bird
            }
        case .limit:
            if usage.isEmpty {
                bird
            } else {
                Text("\(bird) \(limit)%")
            }
        }
    }
}
