import AppKit
import Foundation
import os
import TendbarApplication
import TendbarDomain
@preconcurrency import UserNotifications

/// Notification Center behind the `AlertPresenting` and `NotificationPermissions` ports.
@MainActor
final class UserNotificationsAlerts: NSObject, UNUserNotificationCenterDelegate, AlertPresenting, NotificationPermissions {
    private let center = UNUserNotificationCenter.current()
    private let log = Logger(subsystem: "pl.dabusoft.tendbar", category: "notifications")
    /// Called with the session id when the user clicks a banner.
    var onOpen: ((String) -> Void)?
    /// Called with the prompt id, the session id and the choice when the user presses Allow or Deny.
    var onAnswer: ((String, String, PermissionDecision) -> Void)?

    private static let permissionCategory = "permission"
    /// A request not shown whole: only Deny, since Allow would approve what the banner leaves out.
    private static let partialPermissionCategory = "permission-partial"
    private static let allowAction = "allow"
    private static let denyAction = "deny"

    override init() {
        super.init()
        center.delegate = self
        let allow = UNNotificationAction(identifier: Self.allowAction, title: String(localized: "Allow"), options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: Self.denyAction, title: String(localized: "Deny"), options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.permissionCategory, actions: [allow, deny], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.partialPermissionCategory, actions: [deny], intentIdentifiers: []),
        ])
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

    func sendTest(sound: AlertSound) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Tendbar"
        content.body = String(localized: "Notifications work.")
        content.sound = Self.sound(sound)
        let previous = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("test-") }
        center.removeDeliveredNotifications(withIdentifiers: previous)
        try await center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: nil))
        await playBirdCall(sound, call: "tendbar-done")
    }

    func present(_ kind: AlertKind, for session: Session, sound: AlertSound) {
        let content = UNMutableNotificationContent()
        content.title = session.displayName
        content.subtitle = session.alertSubtitle(for: kind)
        content.body = session.alertBody(for: kind)
        content.threadIdentifier = session.id
        content.userInfo = ["sessionID": session.id]
        content.sound = Self.sound(sound)
        add(UNNotificationRequest(identifier: Self.identifier(session.id), content: content, trigger: nil), sound: sound, call: Self.call(for: kind))
    }

    /// The tool on the subtitle and the whole command in the body, so Allow never approves something unseen. A request
    /// that does not fit gets Deny only and says so.
    func presentPermission(_ ask: PermissionAsk, for session: Session, sound: AlertSound) {
        let content = UNMutableNotificationContent()
        content.title = session.displayName
        content.subtitle = String(localized: "Allow \(ask.tool)?")
        let body = ask.detail ?? session.message ?? session.state.hint
        content.body = ask.shownInFull ? body : String(localized: "\(body)\n\nNot all of this request fits here. To allow it, answer in the terminal")
        content.threadIdentifier = session.id
        content.categoryIdentifier = ask.shownInFull ? Self.permissionCategory : Self.partialPermissionCategory
        content.userInfo = ["sessionID": session.id, "askID": ask.id]
        content.sound = Self.sound(sound)
        add(UNNotificationRequest(identifier: Self.identifier(session.id), content: content, trigger: nil), sound: sound, call: "tendbar-waiting")
    }

    func presentLimit(_ warning: LimitWarning, account: AccountUsage, sound: AlertSound) {
        let content = UNMutableNotificationContent()
        let reset = warning.resetsAt.formatted(.relative(presentation: .named))
        content.title = String(localized: "\(LimitWindowName.of(warning.window)) limit: \(Int(warning.percentage.rounded()))%")
        content.body = String(localized: "\(account.displayName), resets \(reset)")
        content.threadIdentifier = "limits"
        content.sound = Self.sound(sound)
        let key = LimitWarnings.key(accountID: warning.accountID, window: warning.window, resetsAt: warning.resetsAt, threshold: warning.threshold)
        add(UNNotificationRequest(identifier: "limit-\(key)", content: content, trigger: nil), sound: sound, call: warning.threshold >= 90 ? "tendbar-error" : "tendbar-waiting")
    }

    func presentLimitReset(_ reset: LimitReset, account: AccountUsage, sound: AlertSound) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(LimitWindowName.of(reset.window)) limit is available again")
        content.body = account.displayName
        content.threadIdentifier = "limits"
        content.sound = Self.sound(sound)
        let key = LimitWarnings.resetKey(accountID: reset.accountID, window: reset.window, resetsAt: reset.resetsAt)
        add(UNNotificationRequest(identifier: "limit-\(key)", content: content, trigger: nil), sound: sound, call: "tendbar-done")
    }

    func dismiss(sessionID: String) {
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier(sessionID)])
    }

    private func add(_ request: UNNotificationRequest, sound: AlertSound, call: String) {
        Task {
            do {
                try await center.add(request)
                await playBirdCall(sound, call: call)
            } catch {
                log.error("post failed: \(error, privacy: .public)")
            }
        }
    }

    /// Notification Center on macOS 27 does not play a sound named from the app: it logs "Playing notification
    /// sound { nam: tendbar-done.wav }" and the sound server plays a built-in one instead. So the bird calls play
    /// here, once the banner is posted, and only while sound is on for Tendbar in System Settings → Notifications.
    private func playBirdCall(_ sound: AlertSound, call: String) async {
        guard sound == .bird, await center.notificationSettings().soundSetting == .enabled else { return }
        guard let bird = NSSound(named: call) else {
            log.error("bird call missing: \(call, privacy: .public)")
            return
        }
        bird.stop()
        bird.play()
    }

    /// Tendbar's bird call for each kind, from the bundled sounds that `tools/make-sounds.swift` synthesizes.
    private static func call(for kind: AlertKind) -> String {
        switch kind {
        case .needsYou, .reminder, .quiet: "tendbar-waiting"
        case .done: "tendbar-done"
        case .failed: "tendbar-error"
        }
    }

    /// The banner carries only the system sound; a bird call is played by `playBirdCall`.
    private static func sound(_ sound: AlertSound) -> UNNotificationSound? {
        sound == .system ? .default : nil
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
        let info = response.notification.request.content.userInfo
        guard let sessionID = info["sessionID"] as? String else { return }
        let decision: PermissionDecision? = switch response.actionIdentifier {
        case Self.allowAction: .allow
        case Self.denyAction: .deny
        default: nil
        }
        if let decision, let askID = info["askID"] as? String {
            await MainActor.run { self.onAnswer?(askID, sessionID, decision) }
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run { self.onOpen?(sessionID) }
        }
    }
}
