import AppKit
import TendbarApplication
import TendbarDomain
import TendbarInfrastructure

/// Carries out the plan from `TerminalJump` behind the `TerminalNavigating` port: AppleScript for iTerm2 and
/// Terminal, the terminal's own command line for WezTerm, kitty and tmux, the session folder for VS Code, and the
/// Claude desktop app's link to the session.
@MainActor
final class AppleScriptTerminalNavigator: TerminalNavigating {
    private let tools: TerminalTools
    private let runner: CommandRunning

    init(tools: TerminalTools = .installed, runner: CommandRunning = ProcessCommandRunner()) {
        self.tools = tools
        self.runner = runner
    }

    func jump(to session: Session) -> JumpOutcome {
        perform(TerminalJump.plan(for: session.terminal, folder: session.cwd, tools: tools))
    }

    private func perform(_ plan: JumpPlan) -> JumpOutcome {
        switch plan {
        case .unavailable:
            return .unavailable
        case let .activate(bundleID):
            return activate(bundleID) ? .activated : .notRunning
        case let .script(source, bundleID):
            guard let app = running(bundleID) else { return .notRunning }
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                app.activate()
                let code = error[NSAppleScript.errorNumber] as? Int
                let message = error[NSAppleScript.errorMessage] as? String ?? String(describing: error)
                return code == -1743 ? .notAuthorized(app: app.localizedName ?? bundleID) : .failed(message)
            }
            if result?.stringValue == TerminalJump.found { return .jumped }
            app.activate()
            return .activated
        case let .command(command, bundleID):
            guard let app = running(bundleID) else { return .notRunning }
            let succeeded = runner.run(command).succeeded
            app.activate()
            return succeeded ? .jumped : .activated
        case let .openFolder(folder, bundleID):
            guard let app = running(bundleID), let appURL = app.bundleURL else { return .notRunning }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else {
                app.activate()
                return .activated
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: appURL, configuration: configuration)
            return .jumped
        case let .openURL(link, bundleID):
            guard running(bundleID) != nil, let url = URL(string: link) else { return .notRunning }
            NSWorkspace.shared.open(url)
            return .jumped
        case let .tmux(target):
            let client = target.select(using: runner)
            let outcome = perform(TerminalJump.plan(for: target.host(clientTTY: client), tools: tools))
            return client != nil && outcome == .activated ? .jumped : outcome
        }
    }

    private func running(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    private func activate(_ bundleID: String) -> Bool {
        guard let app = running(bundleID) else { return false }
        app.activate()
        return true
    }
}
