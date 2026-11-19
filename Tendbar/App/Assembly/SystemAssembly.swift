import TendbarApplication

/// Builds the system feature: notification permission, the test banner and glow, opening at login.
@MainActor
struct SystemAssembly {
    let controller: SystemController

    init(_ a: AppContainer.Adapters, model: SystemViewModel, preferences: Preferences) {
        controller = SystemController(
            model: model,
            checkPermission: CheckNotificationPermission(permissions: a.permissions),
            requestPermission: RequestNotificationPermission(permissions: a.permissions),
            sendTest: SendTestNotification(permissions: a.permissions, settings: preferences),
            previewFlash: PreviewScreenFlash(flasher: a.flasher),
            checkLaunchAtLogin: CheckLaunchAtLogin(loginItems: a.loginItems),
            setLaunchAtLogin: SetLaunchAtLogin(loginItems: a.loginItems)
        )
    }
}
