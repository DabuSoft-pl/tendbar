import Foundation
import TendbarApplication
import TendbarDomain

@MainActor
final class InMemorySessions: SessionRepository, SessionsOutput {
    var store: SessionStore
    private(set) var shown: [SessionStore] = []

    init(_ sessions: [Session] = []) {
        store = SessionStore(sessions: sessions)
    }

    func load() -> SessionStore { store }
    func save(_ store: SessionStore) { self.store = store }
    func show(_ sessions: SessionStore) { shown.append(sessions) }
}

@MainActor
final class InMemoryUsage: UsageRepository, UsageOutput {
    var store: UsageStore
    private(set) var shown: [UsageStore] = []

    init(_ accounts: [AccountUsage] = []) {
        store = UsageStore(accounts: accounts)
    }

    func load() -> UsageStore { store }
    func save(_ store: UsageStore) { self.store = store }
    func show(_ usage: UsageStore) { shown.append(usage) }
}

@MainActor
final class InMemoryFiredWarnings: FiredWarningRepository {
    var keys: Set<String> = []
    func load() -> Set<String> { keys }
    func save(_ keys: Set<String>) { self.keys = keys }
}

@MainActor
final class InMemoryProfiles: ProfileRepository {
    var directories: [String] = []
    func load() -> [String] { directories }
    func save(_ directories: [String]) { self.directories = directories }
}

@MainActor
final class RecordingAlerts: AlertPresenting {
    private(set) var presented: [(AlertKind, Session)] = []
    private(set) var limits: [LimitWarning] = []
    private(set) var dismissed: [String] = []

    func present(_ kind: AlertKind, for session: Session, sound: Bool) { presented.append((kind, session)) }
    func presentLimit(_ warning: LimitWarning, account: AccountUsage, sound: Bool) { limits.append(warning) }
    func dismiss(sessionID: String) { dismissed.append(sessionID) }
}

@MainActor
final class RecordingFlasher: ScreenFlashing {
    private(set) var tones: [FlashTone] = []
    func flash(_ tone: FlashTone) { tones.append(tone) }
}

@MainActor
final class StubSettings: AlertSettingsProviding {
    var alertSettings = AlertSettings()
}

@MainActor
final class StubNavigator: TerminalNavigating {
    var outcome: JumpOutcome = .jumped
    private(set) var jumps: [TerminalContext] = []

    func jump(to terminal: TerminalContext) -> JumpOutcome {
        jumps.append(terminal)
        return outcome
    }
}

@MainActor
final class StubEmails: AccountEmailResolving {
    var emails: [String?: String] = [:]
    func email(configDirectory: String?) -> String? { emails[configDirectory] ?? nil }
}

@MainActor
final class StubConnector: HookConnecting {
    var statuses: [String?: HookConnection] = [:]
    private(set) var connected: [String?] = []

    func status(configDirectory: String?) throws -> HookConnection { statuses[configDirectory] ?? .disconnected }
    func connect(configDirectory: String?) throws { connected.append(configDirectory); statuses[configDirectory] = .connected }
    func disconnect(configDirectory: String?) throws { statuses[configDirectory] = .disconnected }
}

@MainActor
final class StubDirectories: ProfileDirectories {
    func create(named name: String) throws -> String { "/Users/me/.claude-\(name)" }
}

struct StubTranscripts: TranscriptReading {
    var preview: String?
    func lastReplyPreview(at path: String) async -> String? { preview }
}

struct FixedClock: Clock {
    var date: Date
    func now() -> Date { date }
}
