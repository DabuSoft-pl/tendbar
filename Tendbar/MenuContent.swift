import AppKit
import SwiftUI
import TendbarKit

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let error = model.startError {
                Text("Nie udało się uruchomić odbiornika: \(error)")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            Divider()
            if model.events.isEmpty {
                Text("Brak zdarzeń. Dodaj hook Claude Code, żeby zobaczyć pierwsze.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.events) { EventRow(event: $0) }
                    }
                }
                .frame(maxHeight: 360)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text("Tendbar").font(.headline)
            Spacer()
            Text("Zdarzenia: \(model.events.count)")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Button("Pokaż log") {
                NSWorkspace.shared.activateFileViewerSelecting([TendbarPaths.eventLog])
            }
            if let path = model.hookExecutablePath {
                Button("Kopiuj ścieżkę hooka") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
            }
            Spacer()
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
        }
    }
}

struct EventRow: View {
    let event: ReceivedEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Text(event.envelope.sentAt, style: .time)
                    .foregroundStyle(.secondary)
            }
            Text(details)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .font(.callout)
    }

    private var title: String {
        guard let payload = event.payload else { return String(localized: "Nieczytelne zdarzenie") }
        return HookEventName.label(for: payload.event)
    }

    private var details: String {
        let folder = event.payload?.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?"
        let terminal = event.envelope.terminal.program ?? String(localized: "nieznany terminal")
        let tty = event.envelope.terminal.tty ?? "—"
        return "\(folder) · \(terminal) · \(tty)"
    }
}

enum HookEventName {
    static func label(for event: String) -> String {
        switch event {
        case "SessionStart": String(localized: "Start sesji")
        case "UserPromptSubmit": String(localized: "Nowe polecenie")
        case "Notification": String(localized: "Czeka na Ciebie")
        case "PermissionRequest": String(localized: "Prosi o zgodę")
        case "Stop": String(localized: "Gotowe")
        case "StopFailure": String(localized: "Błąd")
        case "SessionEnd": String(localized: "Koniec sesji")
        default: event
        }
    }
}
