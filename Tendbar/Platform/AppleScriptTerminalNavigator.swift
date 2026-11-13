import AppKit
import TendbarApplication
import TendbarDomain
import TendbarInfrastructure

/// Runs the AppleScript plan from `TerminalJump` behind the `TerminalNavigating` port.
@MainActor
final class AppleScriptTerminalNavigator: TerminalNavigating {
    func jump(to terminal: TerminalContext) -> JumpOutcome {
        switch TerminalJump.plan(for: terminal) {
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
