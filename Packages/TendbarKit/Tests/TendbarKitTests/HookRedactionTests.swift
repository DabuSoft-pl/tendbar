import Foundation
import Testing
@testable import TendbarKit

@Suite struct HookRedactionTests {
    @Test func keepsOnlyWhatTendbarUses() throws {
        let input = Data(#"""
        {"session_id":"s1","hook_event_name":"PostToolUse","cwd":"/p","prompt":"secret plan",
         "tool_input":{"command":"export TOKEN=abc"},"tool_response":{"stdout":"file contents"},
         "last_assistant_message":"answer","message":"needs permission","notification_type":"permission_prompt"}
        """#.utf8)

        let redacted = HookRedaction.redact(input, statusLine: false)
        let object = try #require(JSONSerialization.jsonObject(with: Data(redacted.utf8)) as? [String: Any])

        #expect(Set(object.keys) == ["session_id", "hook_event_name", "cwd", "message", "notification_type"])
        #expect(!redacted.contains("secret"))
        #expect(!redacted.contains("TOKEN"))
        #expect(!redacted.contains("file contents"))
    }

    @Test func statusLineKeepsOnlyRateLimits() throws {
        let input = Data(#"{"session_id":"s1","rate_limits":{"five_hour":{"used_percentage":5,"resets_at":1}},"cost":{"total":1},"workspace":{"current_dir":"/p"}}"#.utf8)

        let object = try #require(JSONSerialization.jsonObject(with: Data(HookRedaction.redact(input, statusLine: true).utf8)) as? [String: Any])

        #expect(Set(object.keys) == ["session_id", "rate_limits"])
    }

    @Test func unreadableInputBecomesEmpty() {
        #expect(HookRedaction.redact(Data("not json".utf8), statusLine: false) == "{}")
    }
}
