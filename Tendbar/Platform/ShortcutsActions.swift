import AppIntents

/// Actions for the Shortcuts app. They read the running app's state; macOS starts Tendbar first when it is not running.
struct WaitingSessionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Sessions Waiting for You"
    static let description = IntentDescription("How many Claude Code sessions wait for your answer or permission.")

    @Dependency private var container: AppContainer

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: container.sessions.needsYouCount)
    }
}

struct OpenNextSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Next Session"
    static let description = IntentDescription("Bring the terminal tab of the next session that needs you to the front. Returns false when none waits.")

    @Dependency private var container: AppContainer

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: container.sessionActions.openNextSession())
    }
}

struct CurrentLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "Current Account Limit"
    static let description = IntentDescription("The higher of the current account's five-hour and weekly usage, in percent.")

    @Dependency private var container: AppContainer

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: Int(container.usage.currentLimit.rounded()))
    }
}
