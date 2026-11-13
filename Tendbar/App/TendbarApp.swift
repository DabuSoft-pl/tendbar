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
            MenuBarLabel(sessions: container.sessions, usage: container.usage)
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

    var body: some View {
        let limit = Int(usage.currentLimit.rounded())
        if sessions.needsYouCount > 0 {
            Text("\(Image(systemName: "bird.fill")) \(sessions.needsYouCount)")
        } else if limit >= 90 {
            Text("\(Image(systemName: "bird")) \(limit)%")
        } else {
            Image(systemName: "bird")
        }
    }
}
