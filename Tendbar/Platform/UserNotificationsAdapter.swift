import Foundation
import os
import TendbarApplication
import TendbarDomain
@preconcurrency import UserNotifications

/// Notification Center behind the `AlertPresenting` and `NotificationPermissions` ports.
@MainActor
final class UserNotificationsAdapter: NSObject, UNUserNotificationCenterDelegate, AlertPresenting, NotificationPermissions {
    private let center = UNUserNotificationCenter.current()
    private let log = Logger(subsystem: "pl.dabusoft.tendbar", category: "notifications")
    /// Called with the session id when the user clicks a banner.
    var onOpen: ((String) -> Void)?
    /// Called with the prompt id, the session id and the choice when the user presses Allow or Deny.
    var onAnswer: ((String, String, PermissionDecision) -> Void)?

    private static let permissionCategory = "permission"
    private static let allowAction = "allow"
    private static let denyAction = "deny"

    override init() {
        super.init()
        center.delegate = self
        let allow = UNNotificationAction(identifier: Self.allowAction, title: String(localized: "Allow"), options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: Self.denyAction, title: String(localized: "Deny"), options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.permissionCategory, actions: [allow, deny], intentIdentifiers: []),
        ])
        installSounds()
    }

    /// Notification Center looks a named sound up in the bundle of whichever copy of the app Launch Services finds
    /// first for our bundle id. An old build without the bird calls (in DerivedData, say) makes every banner
    /// silent, so the calls also go to ~/Library/Sounds, which is searched whatever copy it picks.
    private func installSounds() {
        let files = FileManager.default
        guard let library = files.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let folder = library.appendingPathComponent("Sounds", isDirectory: true)
        for call in ["tendbar-waiting", "tendbar-done", "tendbar-error"] {
            guard let source = Bundle.main.url(forResource: call, withExtension: "wav") else { continue }
            let target = folder.appendingPathComponent("\(call).wav")
            do {
                let data = try Data(contentsOf: source)
                if (try? Data(contentsOf: target)) == data { continue }
                try files.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
            } catch {
                log.error("sound install failed: \(error, privacy: .public)")
            }
        }
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
        content.sound = Self.sound(sound, call: "tendbar-done")
        let previous = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("test-") }
        center.removeDeliveredNotifications(withIdentifiers: previous)
        try await center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: nil))
    }

    func present(_ kind: AlertKind, for session: Session, sound: AlertSound) {
        let content = UNMutableNotificationContent()
        content.title = session.folderName
        content.subtitle = session.alertSubtitle(for: kind)
        content.body = session.alertBody(for: kind)
        content.threadIdentifier = session.id
        content.userInfo = ["sessionID": session.id]
        content.sound = Self.sound(sound, call: Self.call(for: kind))
        add(UNNotificationRequest(identifier: Self.identifier(session.id), content: content, trigger: nil))
    }

    /// The tool on the subtitle and the whole command in the body, so Allow never approves something unseen.
    func presentPermission(_ ask: PermissionAsk, for session: Session, sound: AlertSound) {
        let content = UNMutableNotificationContent()
        content.title = session.folderName
        content.subtitle = String(localized: "Allow \(ask.tool)?")
        content.body = ask.detail ?? session.message ?? session.state.hint
        content.threadIdentifier = session.id
        content.categoryIdentifier = Self.permissionCategory
        content.userInfo = ["sessionID": session.id, "askID": ask.id]
        content.sound = Self.sound(sound, call: "tendbar-waiting")
        add(UNNotificationRequest(identifier: Self.identifier(session.id), content: content, trigger: nil))
    }

    func presentLimit(_ warning: LimitWarning, account: AccountUsage, sound: AlertSound) {
        let content = UNMutableNotificationContent()
        let reset = warning.resetsAt.formatted(.relative(presentation: .named))
        content.title = String(localized: "\(LimitWindowName.of(warning.window)) limit: \(Int(warning.percentage.rounded()))%")
        content.body = String(localized: "\(account.displayName), resets \(reset)")
        content.threadIdentifier = "limits"
        content.sound = Self.sound(sound, call: warning.threshold >= 90 ? "tendbar-error" : "tendbar-waiting")
        let key = LimitWarnings.key(accountID: warning.accountID, window: warning.window, resetsAt: warning.resetsAt, threshold: warning.threshold)
        add(UNNotificationRequest(identifier: "limit-\(key)", content: content, trigger: nil))
    }

    func presentLimitReset(_ reset: LimitReset, account: AccountUsage, sound: AlertSound) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(LimitWindowName.of(reset.window)) limit is available again")
        content.body = account.displayName
        content.threadIdentifier = "limits"
        content.sound = Self.sound(sound, call: "tendbar-done")
        let key = LimitWarnings.resetKey(accountID: reset.accountID, window: reset.window, resetsAt: reset.resetsAt)
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

    /// Tendbar's bird call for each kind, from the bundled sounds that `tools/make-sounds.swift` synthesizes.
    private static func call(for kind: AlertKind) -> String {
        switch kind {
        case .needsYou, .reminder, .quiet: "tendbar-waiting"
        case .done: "tendbar-done"
        case .failed: "tendbar-error"
        }
    }

    private static func sound(_ sound: AlertSound, call: String) -> UNNotificationSound? {
        switch sound {
        case .none: nil
        case .system: .default
        case .bird: UNNotificationSound(named: UNNotificationSoundName("\(call).wav"))
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
