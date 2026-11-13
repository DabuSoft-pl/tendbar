import TendbarDomain

/// Forgets a profile. Its directory stays on disk.
@MainActor
public final class RemoveProfile {
    private let repository: ProfileRepository

    public init(repository: ProfileRepository) {
        self.repository = repository
    }

    public func execute(directory: String) {
        repository.save(repository.load().filter { $0 != directory })
    }
}
