import SwiftUI

@main
struct TendbarApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            if model.needsYouCount > 0 {
                Text("\(Image(systemName: "bird.fill")) \(model.needsYouCount)")
            } else {
                Image(systemName: "bird")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
