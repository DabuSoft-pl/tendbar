import TendbarDomain

/// Where session state is kept between launches.
@MainActor
public protocol SessionRepository: AnyObject {
    func load() -> SessionStore
    func save(_ store: SessionStore)
}

/// Where limit readings are kept between launches.
@MainActor
public protocol UsageRepository: AnyObject {
    func load() -> UsageStore
    func save(_ store: UsageStore)
}

/// Limit warnings already shown, so a threshold warns once per window.
@MainActor
public protocol FiredWarningRepository: AnyObject {
    func load() -> Set<String>
    func save(_ keys: Set<String>)
}

/// Extra Claude Code profile directories the user added.
@MainActor
public protocol ProfileRepository: AnyObject {
    func load() -> [String]
    func save(_ directories: [String])
}
