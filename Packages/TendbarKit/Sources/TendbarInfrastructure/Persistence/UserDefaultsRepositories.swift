import Foundation
import TendbarApplication

@MainActor
public final class UserDefaultsFiredWarningRepository: FiredWarningRepository {
    public static let key = "limits.fired"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    public func save(_ keys: Set<String>) {
        defaults.set(keys.sorted(), forKey: Self.key)
    }
}

@MainActor
public final class UserDefaultsProfileRepository: ProfileRepository {
    public static let key = "profiles"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    public func save(_ directories: [String]) {
        defaults.set(directories, forKey: Self.key)
    }
}
