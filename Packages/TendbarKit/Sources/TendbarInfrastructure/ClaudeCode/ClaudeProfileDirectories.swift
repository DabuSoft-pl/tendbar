import Foundation
import TendbarApplication

@MainActor
public final class ClaudeProfileDirectories: ProfileDirectories {
    public init() {}

    public func create(named name: String) throws -> String {
        do {
            return try ClaudeProfiles.create(named: name).path
        } catch ClaudeProfileError.invalidName {
            throw ProfileCreationError.invalidName
        } catch {
            throw ProfileCreationError.failed(error.localizedDescription)
        }
    }
}
