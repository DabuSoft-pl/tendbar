@MainActor
public final class CheckLaunchAtLogin {
    private let loginItems: LoginItemControlling

    public init(loginItems: LoginItemControlling) {
        self.loginItems = loginItems
    }

    public func execute() -> LoginItemState {
        loginItems.state
    }
}

@MainActor
public final class SetLaunchAtLogin {
    private let loginItems: LoginItemControlling

    public init(loginItems: LoginItemControlling) {
        self.loginItems = loginItems
    }

    /// Returns the state after the change; throws when macOS refused it.
    public func execute(enabled: Bool) throws -> LoginItemState {
        try loginItems.setEnabled(enabled)
        return loginItems.state
    }
}
