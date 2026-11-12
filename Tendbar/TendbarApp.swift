import SwiftUI

@main
struct TendbarApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: "bird")
        }
        .menuBarExtraStyle(.window)
    }
}
