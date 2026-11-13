import AppKit
import TendbarKit

enum JumpResult: Equatable {
    case jumped
    case activated
    case notRunning
    case unavailable
    case notAuthorized(String)
    case failed(String)
}

@MainActor
enum TerminalJumper {
    static func jump(to context: TerminalContext) -> JumpResult {
        switch TerminalJump.plan(for: context) {
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
                return code == -1743 ? .notAuthorized(app.localizedName ?? bundleID) : .failed(message)
            }
            if result?.stringValue == TerminalJump.found { return .jumped }
            app.activate()
            return .activated
        }
    }

    private static func running(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    private static func activate(_ bundleID: String) -> Bool {
        guard let app = running(bundleID) else { return false }
        app.activate()
        return true
    }
}
