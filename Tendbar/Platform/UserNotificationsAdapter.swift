import Foundation
import os
import TendbarApplication
import TendbarDomain
import UserNotifications

/// Notification Center behind the `AlertPresenting` and `NotificationPermissions` ports.
@MainActor
final class UserNotificationsAdapter: NSObject, UNUserNotificationCenterDelegate, AlertPresenting, NotificationPermissions {
    private let center = UNUserNotificationCenter.current()
    private let log = Logger(subsystem: "pl.dabusoft.tendbar", category: "notifications")
    /// Called with the session id when the user clicks a banner.
    var onOpen: ((String) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }

    func requestPermission() async -> (NotificationPermission, error: String?) {
        var message: String?
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            log.info("authorization granted: \(granted)")
        } catch {
            log.error("authorization failed: \(error, privacy: .public)")
            message = error.localizedDescription
        }
        return (await permission(), message)
    }

    func sendTest(sound: Bool) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Tendbar"
        content.body = String(localized: "Powiadomienia działają.")
        if sound { content.sound = .default }
        let previous = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("test-") }
        center.removeDeliveredNotifications(withIdentifiers: previous)
        try await center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: nil))
    }

    func present(_ kind: AlertKind, for session: Session, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = session.folderName
        content.subtitle = kind.title
        content.body = session.alertBody(for: kind)
        content.threadIdentifier = session.id
        content.userInfo = ["sessionID": session.id]
        if sound { content.sound = .default }
        add(UNNotificationRequest(identifier: Self.identifier(session.id), content: content, trigger: nil))
    }

    func presentLimit(_ warning: LimitWarning, account: AccountUsage, sound: Bool) {
        let content = UNMutableNotificationContent()
        let reset = warning.resetsAt.formatted(.relative(presentation: .named))
        content.title = String(localized: "Limit \(LimitWindowName.of(warning.window)): \(Int(warning.percentage.rounded()))%")
        content.body = String(localized: "\(account.displayName), reset \(reset)")
        content.threadIdentifier = "limits"
        if sound { content.sound = .default }
        let key = LimitWarnings.key(accountID: warning.accountID, window: warning.window, resetsAt: warning.resetsAt, threshold: warning.threshold)
        add(UNNotificationRequest(identifier: "limit-\(key)", content: content, trigger: nil))
    }

    func dismiss(sessionID: String) {
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier(sessionID)])
    }

    private func add(_ request: UNNotificationRequest) {
        center.add(request) { [log] error in
            if let error { log.error("post failed: \(error, privacy: .public)") }
        }
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
