#if DEBUG
import SwiftUI
import TendbarApplication
import TendbarDomain

@MainActor
enum PreviewData {
    static func container(
        sessions: [Session] = PreviewData.sessions,
        accounts: [AccountUsage] = PreviewData.accounts,
        hooks: [String?: HookConnection] = [:]
    ) -> AppContainer {
        let container = AppContainer.preview(sessions: sessions, accounts: accounts, hooks: hooks)
        if !sessions.isEmpty { container.activity.show(activity) }
        return container
    }

    static var activity: ActivityStats {
        var day = DayActivity()
        day.turns = 23
        day.workSeconds = 2 * 3600 + 14 * 60
        day.waits = 9
        day.waitSeconds = 41 * 60
        day.longestTurn = 26 * 60
        day.longestTurnFolder = "shop-api"
        day.longestWait = 12 * 60
        day.longestWaitFolder = "infra"
        return ActivityStats(days: [ActivityStats.key(for: Date(), calendar: .current): day])
    }

    static var sessions: [Session] {
        [
            session("a1", folder: "shop-api", state: .needsYou, minutesAgo: 1, unread: true,
                    message: "Claude needs your permission to use Bash", title: "Rotate the payment API keys"),
            session("b2", folder: "tendbar", state: .working, minutesAgo: 0.2, turnMinutesAgo: 7,
                    title: "Session names from Claude Code titles"),
            session("c3", folder: "shop-web", state: .done, minutesAgo: 6, unread: true,
                    preview: "The login form now uses the new endpoint and the tests pass.",
                    title: "Move the login form to the new auth endpoint and update its end-to-end tests"),
            session("d4", folder: "infra", state: .failed, minutesAgo: 14, unread: true,
                    message: "API overloaded (529 Overloaded)"),
            session("e5", folder: "vault", state: .done, minutesAgo: 48,
                    preview: "Added a note on the migration and updated the ADR index."),
        ]
    }

    static var accounts: [AccountUsage] {
        [
            account("|alex@example.com", email: "alex@example.com", five: 92, week: 63, minutesAgo: 1),
            account("|work@example.com", email: "work@example.com", five: 41, week: 87, minutesAgo: 180),
        ]
    }

    static func session(
        _ id: String, folder: String, state: SessionState, minutesAgo: Double,
        unread: Bool = false, message: String? = nil, preview: String? = nil, turnMinutesAgo: Double? = nil,
        title: String? = nil
    ) -> Session {
        Session(
            id: id,
            cwd: "/Users/me/Projects/\(folder)",
            terminal: TerminalContext(program: "iTerm.app"),
            state: state,
            startedAt: date(minutesAgo + 30),
            updatedAt: date(minutesAgo),
            turnStartedAt: turnMinutesAgo.map(date),
            unread: unread,
            message: message,
            preview: preview,
            title: title
        )
    }

    static func account(_ id: String, email: String, five: Double, week: Double, minutesAgo: Double) -> AccountUsage {
        AccountUsage(
            id: id,
            email: email,
            fiveHour: LimitWindow(usedPercentage: five, resetsAt: date(-130)),
            sevenDay: LimitWindow(usedPercentage: week, resetsAt: date(-3 * 24 * 60)),
            updatedAt: date(minutesAgo)
        )
    }

    private static func date(_ minutesAgo: Double) -> Date {
        Date().addingTimeInterval(-minutesAgo * 60)
    }
}

private struct NotchPreview: View {
    let container: AppContainer
    var expanded = false

    var body: some View {
        NotchView(
            hover: NotchHover(expanded: expanded),
            sessions: container.sessions,
            usage: container.usage,
            claudeCode: container.claudeCode,
            preferences: container.preferences,
            onSelect: { container.sessionActions.select($0) },
            notchWidth: 180,
            notchHeight: 32
        )
        .frame(width: 420, height: expanded ? 420 : 60)
        .background(.gray.opacity(0.3))
    }
}

#Preview("Panel") {
    MenuContent(container: PreviewData.container())
}

#Preview("Panel, empty") {
    MenuContent(container: PreviewData.container(sessions: [], accounts: []))
}

#Preview("Notch") {
    NotchPreview(container: PreviewData.container())
}

#Preview("Notch, working") {
    NotchPreview(container: PreviewData.container(
        sessions: [PreviewData.session("b2", folder: "tendbar", state: .working, minutesAgo: 1)],
        accounts: [PreviewData.account("|alex@example.com", email: "alex@example.com", five: 33, week: 63, minutesAgo: 1)]
    ))
}

#Preview("Notch, expanded") {
    NotchPreview(container: PreviewData.container(), expanded: true)
}

#Preview("Settings") {
    SettingsView(container: PreviewData.container())
}
#endif
