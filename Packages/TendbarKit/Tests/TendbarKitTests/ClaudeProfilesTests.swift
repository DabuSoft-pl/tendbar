import Foundation
import Testing
@testable import TendbarKit

@Suite struct ClaudeProfilesTests {
    let home: URL
    let source: URL

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("tendbar-home-\(UUID().uuidString)")
        source = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: source.appendingPathComponent("settings.json"))
        try Data("# notes".utf8).write(to: source.appendingPathComponent("CLAUDE.md"))
        try Data("secret".utf8).write(to: source.appendingPathComponent(".credentials.json"))
    }

    private func destination(of link: URL) throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    }

    @Test func createsAProfileThatSharesSettingsButNotTheLogin() throws {
        let profile = try ClaudeProfiles.create(named: "work", home: home)

        #expect(profile.lastPathComponent == ".claude-work")
        #expect(try destination(of: profile.appendingPathComponent("settings.json")) == source.appendingPathComponent("settings.json").path)
        #expect(try destination(of: profile.appendingPathComponent("CLAUDE.md")) == source.appendingPathComponent("CLAUDE.md").path)
        #expect(try destination(of: profile.appendingPathComponent("skills")) == source.appendingPathComponent("skills").path)
        #expect(!FileManager.default.fileExists(atPath: profile.appendingPathComponent(".credentials.json").path))
        #expect(!FileManager.default.fileExists(atPath: profile.appendingPathComponent("agents").path))
    }

    @Test func creatingAgainKeepsWhatIsThere() throws {
        let profile = try ClaudeProfiles.create(named: "work", home: home)
        try FileManager.default.removeItem(at: profile.appendingPathComponent("CLAUDE.md"))
        try Data("# own".utf8).write(to: profile.appendingPathComponent("CLAUDE.md"))

        try ClaudeProfiles.create(named: "work", home: home)

        #expect(try String(contentsOf: profile.appendingPathComponent("CLAUDE.md"), encoding: .utf8) == "# own")
    }

    @Test(arguments: ["", "Work", "a b", "../x", "-x", "x-", String(repeating: "a", count: 33)])
    func rejectsBadNames(_ name: String) {
        #expect(throws: ClaudeProfileError.invalidName) { try ClaudeProfiles.create(named: name, home: home) }
    }

    @Test(arguments: [
        ("jan@example.pl", "jan-example"),
        ("Praca", "praca"),
        ("  Konto prywatne ", "konto-prywatne"),
        ("Żółć & łódź", "zolc-lodz"),
        ("john.doe@gmail.com", "john-doe-gmail"),
        ("--a--b--", "a-b"),
        ("!!!", ""),
    ])
    func slugsAnyInput(input: String, expected: String) {
        #expect(ClaudeProfiles.slug(from: input) == expected)
    }

    @Test func slugIsAlwaysAValidNameOrEmpty() {
        let slug = ClaudeProfiles.slug(from: String(repeating: "ab-", count: 20))
        #expect(slug.count <= 32)
        #expect(ClaudeProfiles.isValidName(slug))
    }

    @Test func launchCommandUsesTilde() {
        let profile = ClaudeProfiles.directory(named: "work", home: home)

        #expect(ClaudeProfiles.launchCommand(for: profile, home: home) == "CLAUDE_CONFIG_DIR=~/.claude-work claude")
    }
}
