import Foundation
import SwiftUI
import TendbarDomain

// How domain values read and look on screen. Kept out of the domain so it stays free of UI concerns.

extension SessionState {
    var label: String {
        switch self {
        case .idle: String(localized: "bezczynna")
        case .working: String(localized: "pracuje")
        case .needsYou: String(localized: "czeka na Ciebie")
        case .done: String(localized: "gotowe")
        case .failed: String(localized: "błąd")
        case .ended: String(localized: "zakończona")
        }
    }

    var hint: String {
        switch self {
        case .idle: String(localized: "Czeka na pierwsze polecenie")
        case .working: String(localized: "Claude pracuje…")
        case .needsYou: String(localized: "Claude potrzebuje Twojej decyzji")
        case .done: String(localized: "Odpowiedź gotowa")
        case .failed: String(localized: "Tura zakończyła się błędem")
        case .ended: String(localized: "Sesja zamknięta")
        }
    }

    var color: Color {
        switch self {
        case .idle, .ended: .gray
        case .working: .blue
        case .needsYou: .orange
        case .done: .green
        case .failed: .red
        }
    }
}

extension AlertKind {
    var title: String {
        switch self {
        case .needsYou: String(localized: "Czeka na Ciebie")
        case .done: String(localized: "Gotowe")
        case .failed: String(localized: "Błąd")
        }
    }
}

extension Session {
    /// The banner text for an alert about this session.
    func alertBody(for kind: AlertKind) -> String {
        switch kind {
        case .needsYou, .failed: message ?? state.hint
        case .done: preview ?? state.hint
        }
    }
}

extension AccountUsage {
    var displayName: String {
        email
            ?? configDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? String(localized: "Konto domyślne")
    }
}

enum LimitWindowName {
    static func of(_ window: String) -> String {
        switch window {
        case LimitWarnings.fiveHour: String(localized: "5 godz.")
        case LimitWarnings.sevenDay: String(localized: "tygodniowy")
        default: window
        }
    }
}

func limitColor(_ percentage: Double) -> Color {
    switch percentage {
    case ..<70: .blue
    case ..<90: .orange
    default: .red
    }
}
