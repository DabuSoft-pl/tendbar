import Foundation
import Testing
import TendbarDomain
@testable import TendbarInfrastructure

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

@Suite struct TranscriptPathTests {
    let home: URL

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("tendbar-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/projects/app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    }

    private func allowed(_ relative: String) -> Bool {
        FileTranscriptReader.transcriptURL(home.appendingPathComponent(relative).path, home: home) != nil
    }

    @Test func acceptsTranscriptsOfEveryProfile() {
        #expect(allowed(".claude/projects/app/s1.jsonl"))
        #expect(allowed(".claude-work/projects/app/s1.jsonl"))
    }

    @Test func refusesEverythingElse() {
        #expect(!allowed("Documents/notes.jsonl"))
        #expect(!allowed(".claude/projects/app/s1.json"))
        #expect(!allowed(".claude/settings.jsonl"))
        #expect(!allowed(".claude/projects/../../Documents/x.jsonl"))
        #expect(FileTranscriptReader.transcriptURL("relative/.claude/projects/a/s.jsonl", home: home) == nil)
        #expect(FileTranscriptReader.transcriptURL("/etc/x.jsonl", home: home) == nil)
    }

    @Test func refusesASymlinkLeadingOutOfProjects() throws {
        let target = home.appendingPathComponent("Documents/secret.jsonl")
        try Data("{}".utf8).write(to: target)
        let link = home.appendingPathComponent(".claude/projects/app/link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(!allowed(".claude/projects/app/link.jsonl"))
    }

    @Test func readsAPreviewOnlyFromAnAllowedPath() async throws {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Tests pass."}]}}"#
        let inside = home.appendingPathComponent(".claude/projects/app/s1.jsonl")
        let outside = home.appendingPathComponent("Documents/s1.jsonl")
        try Data(line.utf8).write(to: inside)
        try Data(line.utf8).write(to: outside)
        let reader = FileTranscriptReader(home: home)

        #expect(await reader.lastReplyPreview(at: inside.path) == "Tests pass.")
        #expect(await reader.lastReplyPreview(at: outside.path) == nil)
    }
}
