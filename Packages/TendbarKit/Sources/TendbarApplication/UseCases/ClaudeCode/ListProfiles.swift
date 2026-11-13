import TendbarDomain

public struct ProfileSummary: Sendable, Equatable, Identifiable {
    /// Nil for the default `~/.claude`.
    public var directory: String?
    public var email: String?
    public var connection: HookConnection?

    public init(directory: String?, email: String?, connection: HookConnection?) {
        self.directory = directory
        self.email = email
        self.connection = connection
    }

    public var id: String { directory ?? "" }

    public var launchCommand: String {
        ProfileName.launchCommand(for: directory)
    }
}

@MainActor
public final class ListProfiles {
    private let repository: ProfileRepository
    private let emails: AccountEmailResolving
    private let connector: HookConnecting?

    public init(repository: ProfileRepository, emails: AccountEmailResolving, connector: HookConnecting?) {
        self.repository = repository
        self.emails = emails
        self.connector = connector
    }

    public func execute() -> [ProfileSummary] {
        ([nil] + repository.load().map(Optional.some)).map { directory in
            ProfileSummary(
                directory: directory,
                email: emails.email(configDirectory: directory),
                connection: try? connector?.status(configDirectory: directory)
            )
        }
    }
}
