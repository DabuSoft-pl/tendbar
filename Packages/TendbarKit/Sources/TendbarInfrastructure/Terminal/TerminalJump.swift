import Foundation
import TendbarDomain

/// A command line Tendbar runs itself, never through a shell.
public struct TerminalCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]

    public init(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

/// A tmux pane: select it, then reach the terminal tab its client is attached in.
public struct TmuxTarget: Equatable, Sendable {
    public var executable: String
    public var socket: String
    public var pane: String
    /// The terminal tmux runs in, without a TTY: the client's TTY is looked up when jumping.
    public var host: TerminalContext

    func command(_ arguments: String...) -> TerminalCommand {
        TerminalCommand(executable, ["-S", socket] + arguments)
    }

    public var selectCommands: [TerminalCommand] {
        [command("select-window", "-t", pane), command("select-pane", "-t", pane)]
    }

    public var sessionCommand: TerminalCommand {
        command("display-message", "-p", "-t", pane, "#{session_name}")
    }

    public func clientsCommand(session: String?) -> TerminalCommand {
        session.map { command("list-clients", "-t", $0, "-F", "#{client_tty}") }
            ?? command("list-clients", "-F", "#{client_tty}")
    }

    public func switchCommand(client: String) -> TerminalCommand {
        command("switch-client", "-c", client, "-t", pane)
    }

    /// The host terminal with the TTY of the tmux client.
    public func host(clientTTY: String?) -> TerminalContext {
        var context = host
        context.tty = TerminalJump.safe(clientTTY)
        return context
    }
}

public enum JumpPlan: Equatable, Sendable {
    case script(String, bundleID: String)
    case activate(bundleID: String)
    /// Run the terminal's own command line, then bring the app forward.
    case command(TerminalCommand, bundleID: String)
    /// Open the session folder in the editor, which brings its window forward.
    case openFolder(String, bundleID: String)
    case tmux(TmuxTarget)
    case unavailable
}

/// Finds the command line tools of terminals that have them.
public struct TerminalTools: Sendable {
    public var locate: @Sendable (String) -> String?

    public init(locate: @escaping @Sendable (String) -> String?) {
        self.locate = locate
    }

    public static let installed = TerminalTools { name in
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let apps = ["wezterm": "WezTerm.app", "kitty": "kitty.app"]
        var candidates = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"].map { "\($0)/\(name)" }
        if let app = apps[name] {
            candidates.insert(contentsOf: ["/Applications", "\(home)/Applications"].map { "\($0)/\(app)/Contents/MacOS/\(name)" }, at: 0)
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static let none = TerminalTools { _ in nil }
}

public enum TerminalJump {
    public static let iTerm = "com.googlecode.iterm2"
    public static let terminal = "com.apple.Terminal"
    public static let vsCode = "com.microsoft.VSCode"
    public static let kitty = "net.kovidgoyal.kitty"
    public static let wezTerm = "com.github.wez.wezterm"
    public static let found = "found"

    /// Used when the hook did not see `__CFBundleIdentifier`.
    public static let bundleIDs: [String: String] = [
        "iTerm.app": iTerm,
        "Apple_Terminal": terminal,
        "vscode": vsCode,
        "ghostty": "com.mitchellh.ghostty",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "WezTerm": wezTerm,
        "Hyper": "co.zeit.hyper",
    ]

    public static func plan(for context: TerminalContext, folder: String? = nil, tools: TerminalTools = .none) -> JumpPlan {
        if let pane = id(context.tmuxPane, prefix: "%"), let socket = safe(context.tmuxSocket),
           let executable = tools.locate("tmux") {
            var host = context
            host.program = nil
            host.tty = nil
            host.itermSessionID = nil
            host.terminalSessionID = nil
            host.tmuxPane = nil
            host.tmuxSocket = nil
            host.weztermPane = nil
            host.kittyWindowID = nil
            return .tmux(TmuxTarget(executable: executable, socket: socket, pane: pane, host: host))
        }

        let host = safe(context.hostBundleID)
        let mapped = context.program.flatMap { bundleIDs[$0] } ?? (context.kittyWindowID != nil ? kitty : nil)
        guard let bundleID = host ?? mapped else { return .unavailable }
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
            break
        }

        if let pane = id(context.weztermPane), let executable = tools.locate("wezterm") {
            let environment = safe(context.weztermSocket).map { ["WEZTERM_UNIX_SOCKET": $0] } ?? [:]
            return .command(
                TerminalCommand(executable, ["cli", "activate-pane", "--pane-id", pane], environment: environment),
                bundleID: bundleID
            )
        }
        if let window = id(context.kittyWindowID), let socket = safe(context.kittySocket),
           let executable = tools.locate("kitty") {
            return .command(
                TerminalCommand(executable, ["@", "--to", socket, "focus-window", "--match", "id:\(window)"]),
                bundleID: bundleID
            )
        }
        if context.program == "vscode", let folder, folder.hasPrefix("/") {
            return .openFolder(folder, bundleID: bundleID)
        }
        return .activate(bundleID: bundleID)
    }

    /// A pane or window number, optionally after a prefix such as tmux's `%`.
    static func id(_ value: String?, prefix: String = "") -> String? {
        guard let value, value.hasPrefix(prefix) else { return nil }
        let digits = value.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.count <= 12, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        return value
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
