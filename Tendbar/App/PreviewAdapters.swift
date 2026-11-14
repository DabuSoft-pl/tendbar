#if DEBUG
import Foundation
import TendbarApplication
import TendbarDomain

// Stand-ins for the outside world, so SwiftUI previews run the real use cases on sample data
// without files, sockets, notifications or AppleScript.

@MainActor
private final class MemorySessions: SessionRepository {
    var store: SessionStore
    init(_ store: SessionStore) { self.store = store }
    func load() -> SessionStore { store }
    func save(_ store: SessionStore) { self.store = store }
}

@MainActor
private final class MemoryUsage: UsageRepository {
    var store: UsageStore
    init(_ store: UsageStore) { self.store = store }
    func load() -> UsageStore { store }
    func save(_ store: UsageStore) { self.store = store }
}

@MainActor
private final class MemoryFired: FiredWarningRepository {
    var keys: Set<String> = []
    func load() -> Set<String> { keys }
    func save(_ keys: Set<String>) { self.keys = keys }
}

@MainActor
private final class MemoryProfiles: ProfileRepository {
    var directories = ["/Users/me/.claude-work"]
    func load() -> [String] { directories }
    func save(_ directories: [String]) { self.directories = directories }
}

@MainActor
private final class Silent: AlertPresenting, NotificationPermissions, ScreenFlashing, TerminalNavigating,
    AccountEmailResolving, HookConnecting, ProfileDirectories, LoginItemControlling {
    /// Hook states per profile directory, nil for `~/.claude`; a profile left out is connected.
    var hooks: [String?: HookConnection] = [:]
    func present(_ kind: AlertKind, for session: Session, sound: AlertSound) {}
    func presentLimit(_ warning: LimitWarning, account: AccountUsage, sound: AlertSound) {}
    func presentLimitReset(_ reset: LimitReset, account: AccountUsage, sound: AlertSound) {}
    func presentPermission(_ ask: PermissionAsk, for session: Session, sound: AlertSound) {}
    func dismiss(sessionID: String) {}
    func permission() async -> NotificationPermission { .authorized }
    func requestPermission() async -> (NotificationPermission, error: String?) { (.authorized, nil) }
    func sendTest(sound: AlertSound) async throws {}
    func flash(_ tone: FlashTone) {}
    func jump(to session: Session) -> JumpOutcome { .jumped }
    func email(configDirectory: String?) -> String? { configDirectory == nil ? "alex@example.com" : "work@example.com" }
    func status(configDirectory: String?) throws -> HookConnection { hooks[configDirectory] ?? .connected }
    func connect(configDirectory: String?) throws {}
    func disconnect(configDirectory: String?) throws {}
    func create(named name: String) throws -> String { "/Users/me/.claude-\(name)" }
    var state: LoginItemState { .enabled }
    func setEnabled(_ enabled: Bool) throws {}
}

@MainActor
private final class MemoryActivity: ActivityRepository {
    var stats = ActivityStats()
    func load() -> ActivityStats { stats }
    func save(_ stats: ActivityStats) { self.stats = stats }
}

private struct UnknownProcesses: SessionProcessChecking {
    func isRunning(_ terminal: TerminalContext) -> Bool? { nil }
}

private struct NoTranscripts: TranscriptReading {
    func lastReplyPreview(at path: String) async -> String? { nil }
    func title(at path: String) async -> String? { nil }
}

extension AppContainer {
    static func preview(sessions: [Session], accounts: [AccountUsage], hooks: [String?: HookConnection] = [:]) -> AppContainer {
        let silent = Silent()
        silent.hooks = hooks
        UserDefaults.standard.removePersistentDomain(forName: "tendbar.preview")
        let defaults = UserDefaults(suiteName: "tendbar.preview") ?? .standard
        return AppContainer(
            preferences: Preferences(defaults: defaults),
            adapters: Adapters(
                sessions: MemorySessions(SessionStore(sessions: sessions)),
                usage: MemoryUsage(UsageStore(accounts: accounts)),
                activity: MemoryActivity(),
                firedWarnings: MemoryFired(),
                profiles: MemoryProfiles(),
                alerts: silent,
                permissions: silent,
                flasher: silent,
                navigator: silent,
                emails: silent,
                transcripts: NoTranscripts(),
                connector: silent,
                profileDirectories: silent,
                loginItems: silent,
                processes: UnknownProcesses(),
                clock: SystemClock()
            ),
            eventLog: URL(fileURLWithPath: "/tmp/events.jsonl"),
            dataFolder: URL(fileURLWithPath: "/tmp")
        )
    }
}
#endif
