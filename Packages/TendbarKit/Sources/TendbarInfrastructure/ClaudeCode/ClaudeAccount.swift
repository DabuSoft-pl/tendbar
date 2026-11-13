import Foundation
import TendbarApplication

/// Reads which account a Claude Code profile is signed in to, from `<profile>/.claude.json`.
public enum ClaudeAccount {
    public static func configFile(configDirectory: String?) -> URL {
        configDirectory.map { URL(fileURLWithPath: $0).appendingPathComponent(".claude.json") }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    public static func email(configDirectory: String?) -> String? {
        email(in: configFile(configDirectory: configDirectory))
    }

    public static func email(in url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any]
        else { return nil }
        return account["emailAddress"] as? String
    }
}

/// Re-reads `.claude.json` only when it changed. The status line reports several times a second.
@MainActor
public final class AccountEmailCache: AccountEmailResolving {
    private var entries: [String: (modified: Date, email: String?)] = [:]

    public init() {}

    public func email(configDirectory: String?) -> String? {
        let url = ClaudeAccount.configFile(configDirectory: configDirectory)
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard let modified else { return nil }
        if let entry = entries[url.path], entry.modified == modified { return entry.email }
        let email = ClaudeAccount.email(in: url)
        entries[url.path] = (modified, email)
        return email
    }
}
