import Testing
@testable import TendbarKit

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
        for raw in [
            #"{"session_id":"s1","hook_event_name":"UserPromptSubmit"}"#,
            #"{"session_id":"s1","hook_event_name":"PermissionRequest"}"#,
            #"{"session_id":"s1","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Allow Bash?"}"#,
        ] {
            let envelope = HookEnvelope(sentAt: .now, terminal: TerminalContext(), raw: raw)
            let previous = store.sessions["s1"]?.state
            let session = store.apply(try! envelope.payload(), envelope: envelope)
            if let alert = AlertPolicy.alert(from: previous, to: session.state) { alerts.append(alert) }
        }

        #expect(alerts == [.needsYou])
    }
}
