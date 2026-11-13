import AppKit

/// The app's own language choice, stored as `AppleLanguages` in Tendbar's defaults. macOS reads it at launch, so a
/// change takes effect after a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", polish = "pl"

    var id: Self { self }

    static var current: AppLanguage {
        guard let saved = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = saved.first
        else { return .system }
        return AppLanguage(rawValue: String(first.prefix(2))) ?? .system
    }

    /// The language the running app shows, which changes only after a relaunch.
    static let launched: AppLanguage = current

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
