import Foundation

/// The version the app was built as. A beta carries its number in `TendbarBeta` (set by `BETA=<n> make release`),
/// since `CFBundleShortVersionString` stays plain digits.
enum AppVersion {
    private static var info: [String: Any]? { Bundle.main.infoDictionary }

    static var short: String {
        info?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var build: String {
        info?["CFBundleVersion"] as? String ?? "?"
    }

    /// The beta number, or nil for a release.
    static var beta: String? {
        (info?["TendbarBeta"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// "1.1.4", or "1.1.4 beta 2" for a beta.
    static var label: String {
        guard let beta else { return short }
        return String(localized: "\(short) beta \(beta)")
    }
}
