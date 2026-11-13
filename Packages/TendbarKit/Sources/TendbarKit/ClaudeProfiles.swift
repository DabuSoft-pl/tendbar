import Foundation

public enum ClaudeProfileError: Error, Equatable {
    case invalidName
    case notADirectory(String)
}

public enum ClaudeProfiles {
    public static let sharedItems = [
        "settings.json", "CLAUDE.md", "agents", "commands", "skills", "plugins", "output-styles",
    ]

    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static var defaultDirectory: URL {
        home.appendingPathComponent(".claude", isDirectory: true)
    }

    public static func isValidName(_ name: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return (1...32).contains(name.count)
            && name.unicodeScalars.allSatisfy(allowed.contains)
            && !name.hasPrefix("-")
            && !name.hasSuffix("-")
    }

    public static func directory(named name: String, home: URL = home) -> URL {
        home.appendingPathComponent(".claude-\(name)", isDirectory: true)
    }

    @discardableResult
    public static func create(named name: String, home: URL = home, sharingFrom source: URL? = nil) throws -> URL {
        guard isValidName(name) else { throw ClaudeProfileError.invalidName }
        let manager = FileManager.default
        let target = directory(named: name, home: home)
        let source = source ?? home.appendingPathComponent(".claude", isDirectory: true)
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: target.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw ClaudeProfileError.notADirectory(target.path) }
        } else {
            try manager.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        for item in sharedItems {
            let original = source.appendingPathComponent(item)
            let link = target.appendingPathComponent(item)
            guard manager.fileExists(atPath: original.path),
                  (try? manager.attributesOfItem(atPath: link.path)) == nil
            else { continue }
            try manager.createSymbolicLink(at: link, withDestinationURL: original)
        }
        return target
    }

    public static func launchCommand(for directory: URL, home: URL = home) -> String {
        let path = directory.path
        let homePath = home.path
        let shown = path.hasPrefix(homePath + "/") ? "~" + path.dropFirst(homePath.count) : path
        return "CLAUDE_CONFIG_DIR=\(shown) claude"
    }
}
