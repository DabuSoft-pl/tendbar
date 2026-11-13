import AppKit
import TendbarApplication

@MainActor
final class SystemController {
    private let model: SystemViewModel
    private let checkPermission: CheckNotificationPermission
    private let requestPermission: RequestNotificationPermission
    private let sendTest: SendTestNotification
    private let previewFlash: PreviewScreenFlash
    private let checkLaunchAtLogin: CheckLaunchAtLogin
    private let setLaunchAtLogin: SetLaunchAtLogin

    init(
        model: SystemViewModel,
        checkPermission: CheckNotificationPermission,
        requestPermission: RequestNotificationPermission,
        sendTest: SendTestNotification,
        previewFlash: PreviewScreenFlash,
        checkLaunchAtLogin: CheckLaunchAtLogin,
        setLaunchAtLogin: SetLaunchAtLogin
    ) {
        self.model = model
        self.checkPermission = checkPermission
        self.requestPermission = requestPermission
        self.sendTest = sendTest
        self.previewFlash = previewFlash
        self.checkLaunchAtLogin = checkLaunchAtLogin
        self.setLaunchAtLogin = setLaunchAtLogin
    }

    func refresh() {
        model.loginItem = checkLaunchAtLogin.execute()
        Task { model.notificationPermission = await checkPermission.execute() }
    }

    func requestNotifications() {
        Task {
            let (permission, error) = await requestPermission.execute()
            model.notificationPermission = permission
            model.notificationError = error
        }
    }

    func sendTestNotification() {
        Task {
            let (permission, error) = await sendTest.execute()
            model.notificationPermission = permission
            model.notificationError = error
        }
    }

    func showFlash() {
        previewFlash.execute()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            model.loginItem = try setLaunchAtLogin.execute(enabled: enabled)
            model.loginItemError = nil
        } catch {
            model.loginItemError = error.localizedDescription
            model.loginItem = checkLaunchAtLogin.execute()
        }
    }

    func revealEventLog() {
        NSWorkspace.shared.activateFileViewerSelecting([model.eventLog])
    }

    func revealDataFolder() {
        NSWorkspace.shared.open(model.dataFolder)
    }

    func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? "pl.dabusoft.tendbar"
        for string in [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
        ] {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
