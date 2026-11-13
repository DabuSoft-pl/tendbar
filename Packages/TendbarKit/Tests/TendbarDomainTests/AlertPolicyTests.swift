import Foundation
import Testing
@testable import TendbarDomain

@Suite struct AlertPolicyTests {
    @Test(arguments: [
        (SessionState?.some(.working), SessionState.needsYou, AlertKind?.some(.needsYou)),
        (.some(.working), .done, .some(.done)),
        (.some(.working), .failed, .some(.failed)),
        (nil, .needsYou, .some(.needsYou)),
        (.some(.needsYou), .needsYou, nil),
        (.some(.done), .done, nil),
        (.some(.needsYou), .working, nil),
        (.some(.idle), .working, nil),
        (.some(.done), .ended, nil),
        (nil, .idle, nil),
    ])
    func alertsOnlyWhenEnteringAnAttentionState(previous: SessionState?, current: SessionState, expected: AlertKind?) {
        #expect(AlertPolicy.alert(from: previous, to: current) == expected)
    }

    @Test func permissionRequestThenNotificationAlertsOnce() {
        var store = SessionStore()
        var alerts: [AlertKind] = []
        for (name, type) in [("UserPromptSubmit", nil), ("PermissionRequest", nil), ("Notification", "permission_prompt")] as [(String, String?)] {
            let event = HookEvent(sessionID: "s1", kind: HookEvent.Kind(name: name), message: "Allow Bash?", notificationType: type, sentAt: .now)
            let previous = store.sessions["s1"]?.state
            let session = store.apply(event)
            if let alert = AlertPolicy.alert(from: previous, to: session.state) { alerts.append(alert) }
        }

        #expect(alerts == [.needsYou])
    }
}
