import Foundation
import os
import TendbarKit
import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var onOpen: ((String) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    private let log = Logger(subsystem: "pl.dabusoft.tendbar", category: "notifications")
    private(set) var lastError: String?

    func requestAuthorization() async -> UNAuthorizationStatus {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            log.info("authorization granted: \(granted)")
            lastError = nil
        } catch {
            log.error("authorization failed: \(error, privacy: .public)")
            lastError = error.localizedDescription
        }
        return await authorizationStatus()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func post(_ kind: AlertKind, for session: Session, body: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = session.folderName
        content.subtitle = kind.title
        content.body = body
        content.threadIdentifier = session.id
        content.userInfo = ["sessionID": session.id]
        if sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: Self.identifier(session.id), content: content, trigger: nil)
        center.add(request) { [log] error in
            if let error { log.error("post failed: \(error, privacy: .public)") }
        }
    }

    func postTest(sound: Bool) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Tendbar"
        content.body = String(localized: "Powiadomienia działają.")
        if sound { content.sound = .default }
        try await center.add(UNNotificationRequest(identifier: "test", content: content, trigger: nil))
    }

    func postLimit(title: String, body: String, identifier: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "limits"
        if sound { content.sound = .default }
        center.add(UNNotificationRequest(identifier: "limit-\(identifier)", content: content, trigger: nil)) { [log] error in
            if let error { log.error("limit post failed: \(error, privacy: .public)") }
        }
    }

    func clear(_ sessionID: String) {
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier(sessionID)])
    }

    private static func identifier(_ sessionID: String) -> String {
        "session-\(sessionID)"
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let sessionID = response.notification.request.content.userInfo["sessionID"] as? String else { return }
        await MainActor.run { self.onOpen?(sessionID) }
    }
}

extension AlertKind {
    var title: String {
        switch self {
        case .needsYou: String(localized: "Czeka na Ciebie")
        case .done: String(localized: "Gotowe")
        case .failed: String(localized: "Błąd")
        }
    }
}
