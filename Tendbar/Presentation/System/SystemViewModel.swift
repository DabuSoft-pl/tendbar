import Foundation
import Observation
import TendbarApplication

@MainActor
@Observable
final class SystemViewModel {
    var notificationPermission: NotificationPermission = .notDetermined
    var notificationError: String?
    var loginItem: LoginItemState = .disabled
    var loginItemError: String?
    let eventLog: URL
    let dataFolder: URL

    init(eventLog: URL, dataFolder: URL) {
        self.eventLog = eventLog
        self.dataFolder = dataFolder
    }
}
