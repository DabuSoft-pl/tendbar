import Foundation

public enum ClaudeSwapUsage {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-swap-backup/cache/usage.json")
    }

    public static func read(from url: URL = defaultURL) -> [AccountUsage] {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        return file.accounts.values.compactMap { entry in
            guard let email = entry.email, !email.isEmpty, let good = entry.lastGood, let fetchedAt = entry.fetchedAt else { return nil }
            return AccountUsage(
                id: UsageStore.key(configDirectory: nil, email: email),
                configDirectory: nil,
                email: email,
                fiveHour: good.fiveHour?.window,
                sevenDay: good.sevenDay?.window,
                scoped: (good.scoped ?? []).compactMap { scoped in
                    scoped.window.map { ScopedWindow(name: scoped.name ?? "?", window: $0) }
                },
                updatedAt: Date(timeIntervalSince1970: fetchedAt),
                source: .claudeSwap
            )
        }
        .sorted { $0.id < $1.id }
    }

    struct File: Decodable {
        let accounts: [String: Entry]
    }

    struct Entry: Decodable {
        let email: String?
        let lastGood: Good?
        let fetchedAt: Double?
    }

    struct Good: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        let scoped: [Window]?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case scoped
        }
    }

    struct Window: Decodable {
        let name: String?
        let pct: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case name
            case pct
            case resetsAt = "resets_at"
        }

        var window: LimitWindow? {
            guard let pct else { return nil }
            return LimitWindow(usedPercentage: pct, resetsAt: resetsAt.flatMap(ClaudeSwapUsage.date(from:)) ?? .distantFuture)
        }
    }

    static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
