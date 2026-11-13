import SwiftUI

@main
struct TendbarApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: MenuBarLabel.image(text: menuBarText))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }

    private var menuBarText: String? {
        if model.needsYouCount > 0 { return "\(model.needsYouCount)" }
        let limit = Int(model.highestLimit.rounded())
        return limit >= 90 ? "\(limit)%" : nil
    }
}
