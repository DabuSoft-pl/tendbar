import Foundation

/// Rules for naming an extra Claude Code profile (`~/.claude-<name>`).
public enum ProfileName {
    public static func isValid(_ name: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return (1...32).contains(name.count)
            && name.unicodeScalars.allSatisfy(allowed.contains)
            && !name.hasPrefix("-")
            && !name.hasSuffix("-")
    }

    public static func slug(from input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let at = text.firstIndex(of: "@") {
            let local = text[..<at]
            let domain = text[text.index(after: at)...].split(separator: ".").first ?? ""
            text = domain.isEmpty ? String(local) : "\(local)-\(domain)"
        }
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .replacingOccurrences(of: "ł", with: "l")
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        var slug = ""
        for character in folded {
            if allowed.contains(character) {
                slug.append(character)
            } else if !slug.isEmpty, slug.last != "-" {
                slug.append("-")
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.count > 32 {
            slug = String(slug.prefix(32))
            while slug.hasSuffix("-") { slug.removeLast() }
        }
        return slug
    }

    public static func launchCommand(for directory: String?, home: String = NSHomeDirectory()) -> String {
        guard let directory else { return "claude" }
        let shown = directory.hasPrefix(home + "/") ? "~" + directory.dropFirst(home.count) : directory
        return "CLAUDE_CONFIG_DIR=\(shown) claude"
    }
}
