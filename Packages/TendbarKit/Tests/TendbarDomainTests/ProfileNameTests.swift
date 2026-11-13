import Testing
@testable import TendbarDomain

@Suite struct ProfileNameTests {
    @Test(arguments: ["", "Work", "a b", "../x", "-x", "x-", String(repeating: "a", count: 33)])
    func rejectsBadNames(_ name: String) {
        #expect(!ProfileName.isValid(name))
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
        #expect(ProfileName.slug(from: input) == expected)
    }

    @Test func slugIsAlwaysAValidNameOrEmpty() {
        let slug = ProfileName.slug(from: String(repeating: "ab-", count: 20))
        #expect(slug.count <= 32)
        #expect(ProfileName.isValid(slug))
    }

    @Test func launchCommandUsesTilde() {
        #expect(ProfileName.launchCommand(for: "/Users/me/.claude-work", home: "/Users/me") == "CLAUDE_CONFIG_DIR=~/.claude-work claude")
        #expect(ProfileName.launchCommand(for: nil) == "claude")
    }
}
