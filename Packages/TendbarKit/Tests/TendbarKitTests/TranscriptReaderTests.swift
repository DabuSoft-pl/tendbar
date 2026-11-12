import Foundation
import Testing
@testable import TendbarKit

@Suite struct TranscriptReaderTests {
    private func transcript(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tendbar-\(UUID().uuidString).jsonl")
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
        return url
    }

    @Test func findsTheLastAssistantText() throws {
        let url = try transcript([
            #"{"type":"user","message":{"role":"user","content":"run the tests"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Running them now."},{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All 42 tests pass."}]}}"#,
            #"{"type":"system","subtype":"turn_duration"}"#,
        ])

        #expect(TranscriptReader.lastAssistantText(at: url) == "All 42 tests pass.")
    }

    @Test func skipsToolOnlyMessages() throws {
        let url = try transcript([
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"First answer"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{}}]}}"#,
        ])

        #expect(TranscriptReader.lastAssistantText(at: url) == "First answer")
    }

    @Test func readsOnlyTheTailAndSurvivesACutLine() throws {
        let filler = String(repeating: "x", count: 2_000)
        let url = try transcript([
            #"{"type":"assistant","message":{"content":"#,
            #"{"type":"user","message":{"content":"\#(filler)"}}"#,
            #"{"type":"assistant","message":{"content":"tail text"}}"#,
        ])

        #expect(TranscriptReader.lastAssistantText(at: url, tailBytes: 100) == "tail text")
    }

    @Test func missingFileGivesNothing() {
        #expect(TranscriptReader.lastAssistantText(at: URL(fileURLWithPath: "/nonexistent/t.jsonl")) == nil)
    }

    @Test func previewCollapsesWhitespaceAndTruncates() {
        #expect(TranscriptReader.preview(of: "a\n\n  b\tc") == "a b c")
        let long = String(repeating: "word ", count: 100)
        let preview = TranscriptReader.preview(of: long, limit: 20)
        #expect(preview.count == 20)
        #expect(preview.hasSuffix("…"))
    }
}
