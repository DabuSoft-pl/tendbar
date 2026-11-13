import Foundation
import TendbarApplication
import TendbarDomain

/// Keeps sessions in memory and writes them through to `sessions.json` (0600 in a 0700 folder).
@MainActor
public final class JSONSessionRepository: SessionRepository {
    private let url: URL
    private var cached: SessionStore?

    public init(url: URL = TendbarPaths.sessions) {
        self.url = url
    }

    public func load() -> SessionStore {
        if let cached { return cached }
        let store = (try? Data(contentsOf: url))
            .flatMap { try? HookEnvelope.decoder.decode(SessionStoreRecord.self, from: $0) }?
            .store ?? SessionStore()
        cached = store
        return store
    }

    public func save(_ store: SessionStore) {
        cached = store
        guard let data = try? HookEnvelope.encoder.encode(SessionStoreRecord(store)) else { return }
        try? TendbarPaths.writePrivately(data, to: url)
    }
}

/// Keeps limit readings in memory and writes them through to `usage.json`.
@MainActor
public final class JSONUsageRepository: UsageRepository {
    private let url: URL
    private var cached: UsageStore?

    public init(url: URL = TendbarPaths.usage) {
        self.url = url
    }

    public func load() -> UsageStore {
        if let cached { return cached }
        let store = (try? Data(contentsOf: url))
            .flatMap { try? HookEnvelope.decoder.decode(UsageStoreRecord.self, from: $0) }?
            .store ?? UsageStore()
        cached = store
        return store
    }

    public func save(_ store: UsageStore) {
        cached = store
        guard let data = try? HookEnvelope.encoder.encode(UsageStoreRecord(store)) else { return }
        try? TendbarPaths.writePrivately(data, to: url)
    }
}
