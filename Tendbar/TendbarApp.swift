import SwiftUI

@main
struct TendbarApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            let limit = Int(model.highestLimit.rounded())
            if model.needsYouCount > 0 {
                Text("\(Image(systemName: "bird.fill")) \(model.needsYouCount)")
            } else if limit >= 90 {
                Text("\(Image(systemName: "bird")) \(limit)%")
            } else {
                Image(systemName: "bird")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
