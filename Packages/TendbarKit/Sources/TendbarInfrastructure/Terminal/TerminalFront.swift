import Foundation
import TendbarDomain

/// How to tell that a session's tab is the one in front, once its app is the frontmost one.
public enum FrontCheck: Sendable {
    /// The app in front is all that can be known, as with VS Code or the Claude desktop app.
    case app(bundleID: String)
    /// An AppleScript that returns `TerminalFront.yes` when the session's tab is selected.
    case script(String, bundleID: String)
    /// The terminal's own command line; its output says whether the session's pane has focus.
    case command(TerminalCommand, bundleID: String, isFront: @Sendable (String) -> Bool)
    case unknown
}

public enum TerminalFront {
    public static let yes = "yes"

    public static func check(for context: TerminalContext, tools: TerminalTools = .none) -> FrontCheck {
        if let pane = TerminalJump.id(context.tmuxPane, prefix: "%"), let socket = TerminalJump.safe(context.tmuxSocket),
           let executable = tools.locate("tmux"), let bundleID = TerminalJump.bundleID(of: context) {
            // The pane is the active one of the active window; which tab the tmux client sits in is not checked.
            let command = TerminalCommand(executable, ["-S", socket, "display-message", "-p", "-t", pane, "#{window_active}#{pane_active}"])
            return .command(command, bundleID: bundleID) { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "11" }
        }
        guard let bundleID = TerminalJump.bundleID(of: context) else { return .unknown }
        let tty = TerminalJump.safe(context.tty) ?? ""
        switch bundleID {
        case TerminalJump.iTerm:
            let uniqueID = TerminalJump.safe(context.itermSessionID?.split(separator: ":").last.map(String.init)) ?? ""
            guard !uniqueID.isEmpty || !tty.isEmpty else { return .app(bundleID: bundleID) }
            return .script(iTermScript(uniqueID: uniqueID, tty: tty), bundleID: bundleID)
        case TerminalJump.terminal:
            guard !tty.isEmpty else { return .app(bundleID: bundleID) }
            return .script(terminalScript(tty: tty), bundleID: bundleID)
        default:
            break
        }
        if let pane = TerminalJump.id(context.weztermPane), let executable = tools.locate("wezterm") {
            let environment = TerminalJump.safe(context.weztermSocket).map { ["WEZTERM_UNIX_SOCKET": $0] } ?? [:]
            let command = TerminalCommand(executable, ["cli", "list-clients", "--format", "json"], environment: environment)
            return .command(command, bundleID: bundleID) { weztermFocuses(pane: pane, in: $0) }
        }
        if let window = TerminalJump.id(context.kittyWindowID), let socket = TerminalJump.safe(context.kittySocket),
           socket.hasPrefix("unix:"), let executable = tools.locate("kitty") {
            let command = TerminalCommand(executable, ["@", "--to", socket, "ls"])
            return .command(command, bundleID: bundleID) { kittyFocuses(window: window, in: $0) }
        }
        return .app(bundleID: bundleID)
    }

    /// `wezterm cli list-clients --format json`: a client whose focused pane is this one.
    static func weztermFocuses(pane: String, in output: String) -> Bool {
        guard let clients = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]] else { return false }
        return clients.contains { ($0["focused_pane_id"] as? Int).map(String.init) == pane }
    }

    /// `kitty @ ls`: the window with this id is the focused one.
    static func kittyFocuses(window: String, in output: String) -> Bool {
        guard let osWindows = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]] else { return false }
        let windows = osWindows
            .flatMap { $0["tabs"] as? [[String: Any]] ?? [] }
            .flatMap { $0["windows"] as? [[String: Any]] ?? [] }
        return windows.contains { ($0["id"] as? Int).map(String.init) == window && $0["is_focused"] as? Bool == true }
    }

    static func iTermScript(uniqueID: String, tty: String) -> String {
        """
        tell application id "\(TerminalJump.iTerm)"
            set s to current session of current window
            if ("\(uniqueID)" is not "" and unique id of s is "\(uniqueID)") or ("\(tty)" is not "" and tty of s is "\(tty)") then return "\(yes)"
        end tell
        return "no"
        """
    }

    static func terminalScript(tty: String) -> String {
        """
        tell application id "\(TerminalJump.terminal)"
            if tty of selected tab of front window is "\(tty)" then return "\(yes)"
        end tell
        return "no"
        """
    }
}
