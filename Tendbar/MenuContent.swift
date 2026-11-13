import AppKit
import SwiftUI
import TendbarKit

struct MenuContent: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        sessionsPanel
        .padding(16)
        .frame(width: 400)
    }

    private var sessionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let error = model.startError {
                Text("Nie udało się uruchomić odbiornika: \(error)")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            ConnectionBanner(model: model)
            if let message = model.jumpMessage {
                HStack(alignment: .top) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        model.dismissJumpMessage()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Divider()
            if model.sessions.isEmpty {
                Text("Brak sesji. Uruchom Claude Code, a pojawią się tutaj.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(model.sessions) { session in
                            SessionRow(session: session) { model.select(session) }
                        }
                    }
                }
                .frame(height: min(CGFloat(model.sessions.count) * 60, 420))
            }
            if !model.usage.accounts.isEmpty {
                Divider()
                UsageSection(model: model)
            }
            Divider()
            footer
        }
        .onAppear { model.refreshConnection() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tendbar").font(.headline)
            Spacer()
            StateCount(state: .working, count: model.store.count(of: .working))
            StateCount(state: .needsYou, count: model.store.count(of: .needsYou))
            StateCount(state: .done, count: model.store.count(of: .done))
        }
    }

    private var footer: some View {
        HStack {
            Button("Oznacz jako przeczytane") { model.markAllSeen() }
                .disabled(!model.sessions.contains { $0.unread })
            Spacer()
            Button {
                NSApp.activate()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Ustawienia (⌘,)")
            Menu {
                Button("Usuń zakończone sesje") { model.removeEnded() }
                Button("Pokaż log zdarzeń") {
                    NSWorkspace.shared.activateFileViewerSelecting([TendbarPaths.eventLog])
                }
                Divider()
                Button("Zakończ Tendbar") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

struct ConnectionBanner: View {
    let model: AppModel

    var body: some View {
        if let error = model.connectionError {
            banner(Text("Nie udało się zmienić ustawień Claude Code: \(error)"), color: .red, button: false)
        } else if model.connection == .disconnected {
            banner(Text("Tendbar nie jest połączony z Claude Code"), color: .secondary, button: true)
        } else if model.connection == .outdated {
            banner(Text("Hooki Tendbara są nieaktualne albo niepełne"), color: .secondary, button: true)
        } else if model.connection == nil {
            banner(Text("Nie znaleziono pomocnika tendbar-hook w aplikacji"), color: .red, button: false)
        }
    }

    private func banner(_ text: Text, color: Color, button: Bool) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(color)
            text.font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if button {
                Button("Połącz") { model.connect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}

struct StateCount: View {
    let state: SessionState
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                StateMark(state: state, unread: true)
                Text("\(count)").monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .help(state.label)
        }
    }
}

struct SessionRow: View {
    let session: Session
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                StateMark(state: session.state, unread: session.unread)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.folderName).fontWeight(.medium).lineLimit(1)
                        Text(session.state.label).foregroundStyle(.secondary)
                        Spacer()
                        Text(age)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var age: String {
        if Date().timeIntervalSince(session.updatedAt) < 10 { return String(localized: "teraz") }
        return session.updatedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    private var detail: String {
        if let message = session.message { return message }
        if let preview = session.preview, session.state == .done || session.state == .idle { return preview }
        return session.state.hint
    }
}

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
        case .working: .secondary
        case .needsYou: .orange
        case .done: .green
        case .failed: .red
        }
    }
}

struct StateMark: View {
    let state: SessionState
    let unread: Bool

    var body: some View {
        Group {
            switch state {
            case .working:
                Circle().strokeBorder(.secondary, lineWidth: 1.5)
            case .idle, .ended:
                Circle().fill(.tertiary)
            case .done where !unread:
                Circle().fill(.tertiary)
            default:
                Circle().fill(state.color)
            }
        }
        .frame(width: 8, height: 8)
        .help(state.label)
        .accessibilityLabel(unread && state == .done ? String(localized: "\(state.label), nieprzeczytane") : state.label)
    }
}
