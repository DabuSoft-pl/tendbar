import Foundation
import TendbarDomain

public enum JumpPlan: Equatable, Sendable {
    case script(String, bundleID: String)
    case activate(bundleID: String)
    case unavailable
}

public enum TerminalJump {
    public static let iTerm = "com.googlecode.iterm2"
    public static let terminal = "com.apple.Terminal"
    public static let found = "found"

    public static let bundleIDs: [String: String] = [
        "iTerm.app": iTerm,
        "Apple_Terminal": terminal,
        "vscode": "com.microsoft.VSCode",
        "ghostty": "com.mitchellh.ghostty",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "WezTerm": "com.github.wez.wezterm",
        "Hyper": "co.zeit.hyper",
    ]

    public static func plan(for context: TerminalContext) -> JumpPlan {
        guard let program = context.program, let bundleID = bundleIDs[program] else { return .unavailable }
        let tty = safe(context.tty)
        switch bundleID {
        case iTerm:
            let uniqueID = safe(context.itermSessionID?.split(separator: ":").last.map(String.init))
            guard uniqueID != nil || tty != nil else { return .activate(bundleID: bundleID) }
            return .script(iTermScript(uniqueID: uniqueID ?? "", tty: tty ?? ""), bundleID: bundleID)
        case terminal:
            guard let tty else { return .activate(bundleID: bundleID) }
            return .script(terminalScript(tty: tty), bundleID: bundleID)
        default:
            return .activate(bundleID: bundleID)
        }
    }

    static func safe(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 128 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_:/."))
        return value.unicodeScalars.allSatisfy(allowed.contains) ? value : nil
    }

    static func iTermScript(uniqueID: String, tty: String) -> String {
        """
        tell application id "\(iTerm)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if ("\(uniqueID)" is not "" and unique id of s is "\(uniqueID)") or ("\(tty)" is not "" and tty of s is "\(tty)") then
                            select w
                            select t
                            select s
                            activate
                            return "\(found)"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "missing"
        """
    }

    static func terminalScript(tty: String) -> String {
        """
        tell application id "\(terminal)"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return "\(found)"
                    end if
                end repeat
            end repeat
        end tell
        return "missing"
        """
    }
}
