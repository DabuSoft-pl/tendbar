import TendbarDomain

@MainActor
public final class CheckNotificationPermission {
    private let permissions: NotificationPermissions

    public init(permissions: NotificationPermissions) {
        self.permissions = permissions
    }

    public func execute() async -> NotificationPermission {
        await permissions.permission()
    }
}

@MainActor
public final class RequestNotificationPermission {
    private let permissions: NotificationPermissions

    public init(permissions: NotificationPermissions) {
        self.permissions = permissions
    }

    public func execute() async -> (NotificationPermission, error: String?) {
        await permissions.requestPermission()
    }
}

/// Asks for permission if needed, then posts a sample banner.
@MainActor
public final class SendTestNotification {
    private let permissions: NotificationPermissions
    private let settings: AlertSettingsProviding

    public init(permissions: NotificationPermissions, settings: AlertSettingsProviding) {
        self.permissions = permissions
        self.settings = settings
    }

    public func execute() async -> (NotificationPermission, error: String?) {
        var (permission, error) = (await permissions.permission(), String?.none)
        if permission != .authorized {
            (permission, error) = await permissions.requestPermission()
        }
        do {
            try await permissions.sendTest(sound: settings.alertSettings.alertSound)
            return (permission, error)
        } catch {
            return (permission, error.localizedDescription)
        }
    }
}
