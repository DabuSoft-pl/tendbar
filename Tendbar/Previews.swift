#if DEBUG
import SwiftUI
import TendbarKit

@MainActor
enum PreviewData {
    static func model(sessions: [[String: Any]] = PreviewData.sessions, accounts: [[String: Any]] = PreviewData.accounts) -> AppModel {
        AppModel(preview: decode(["sessions": keyed(sessions)]), usage: decode(["accounts": keyed(accounts)]))
    }

    static var sessions: [[String: Any]] {
        [
            session("a1", folder: "dabusoft_api", state: "needsYou", minutesAgo: 1,
                    message: "Claude needs your permission to use Bash"),
            session("b2", folder: "tendbar", state: "working", minutesAgo: 2),
            session("c3", folder: "dabusoft_front", state: "done", minutesAgo: 6, unread: true,
                    preview: "Gotowe: formularz logowania korzysta teraz z nowego endpointu, testy przechodzą."),
            session("d4", folder: "homelab-ansible", state: "failed", minutesAgo: 14,
                    message: "API Error: 529 Overloaded"),
            session("e5", folder: "vault", state: "done", minutesAgo: 48,
                    preview: "Dopisałem notatkę o migracji do Symfony i zaktualizowałem indeks ADR."),
        ]
    }

    static var accounts: [[String: Any]] {
        [
            account("|damian@example.com", email: "damian@example.com", five: 92, week: 63, minutesAgo: 1),
            account("|druga@example.com", email: "druga@example.com", five: 41, week: 87, minutesAgo: 180),
        ]
    }

    static func session(
        _ id: String, folder: String, state: String, minutesAgo: Double,
        unread: Bool = false, message: String? = nil, preview: String? = nil
    ) -> [String: Any] {
        var value: [String: Any] = [
            "id": id,
            "cwd": "/Users/me/Projekty/\(folder)",
            "terminal": ["program": "iTerm.app"],
            "state": state,
            "startedAt": date(minutesAgo + 30),
            "updatedAt": date(minutesAgo),
            "unread": unread,
        ]
        value["message"] = message
        value["preview"] = preview
        return value
    }

    static func account(_ id: String, email: String, five: Double, week: Double, minutesAgo: Double) -> [String: Any] {
        [
            "id": id,
            "email": email,
            "fiveHour": ["usedPercentage": five, "resetsAt": date(-130)],
            "sevenDay": ["usedPercentage": week, "resetsAt": date(-3 * 24 * 60)],
            "updatedAt": date(minutesAgo),
        ]
    }

    private static func date(_ minutesAgo: Double) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-minutesAgo * 60))
    }

    private static func keyed(_ items: [[String: Any]]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: items.map { ($0["id"] as! String, $0) })
    }

    private static func decode<T: Decodable>(_ object: [String: Any]) -> T {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! HookEnvelope.decoder.decode(T.self, from: data)
    }
}

#Preview("Panel") {
    MenuContent(model: PreviewData.model())
}

#Preview("Panel, pusto") {
    MenuContent(model: PreviewData.model(sessions: [], accounts: []))
}

#Preview("Notch") {
    NotchView(model: PreviewData.model(), notchWidth: 180, notchHeight: 32)
        .frame(width: 420, height: 60)
        .background(.gray.opacity(0.3))
}

#Preview("Notch, pracuje") {
    NotchView(
        model: PreviewData.model(
            sessions: [PreviewData.session("b2", folder: "tendbar", state: "working", minutesAgo: 1)],
            accounts: [PreviewData.account("|damian@example.com", email: "damian@example.com", five: 33, week: 63, minutesAgo: 1)]
        ),
        notchWidth: 180, notchHeight: 32
    )
    .frame(width: 420, height: 60)
    .background(.gray.opacity(0.3))
}

#Preview("Notch, rozwinięty") {
    NotchView(model: PreviewData.model(), notchWidth: 180, notchHeight: 32, expanded: true)
        .frame(width: 420, height: 420)
        .background(.gray.opacity(0.3))
}

#Preview("Ustawienia") {
    SettingsView(model: PreviewData.model())
}
#endif
