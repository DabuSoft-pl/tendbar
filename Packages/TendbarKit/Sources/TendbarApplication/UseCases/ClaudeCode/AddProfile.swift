import TendbarDomain

@MainActor
public final class AddProfile {
    private let repository: ProfileRepository
    private let directories: ProfileDirectories

    public init(repository: ProfileRepository, directories: ProfileDirectories) {
        self.repository = repository
        self.directories = directories
    }

    /// Throws `ProfileCreationError`.
    public func execute(name: String) throws {
        guard ProfileName.isValid(name) else { throw ProfileCreationError.invalidName }
        let directory = try directories.create(named: name)
        var known = repository.load()
        if !known.contains(directory) {
            known.append(directory)
            repository.save(known)
        }
    }
}
