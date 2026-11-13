import AppKit
import SwiftUI
import TendbarApplication
import TendbarDomain

struct MenuContent: View {
    let container: AppContainer
    private var sessions: SessionsViewModel { container.sessions }
    private var actions: SessionsController { container.sessionActions }
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        sessionsPanel
        .padding(16)
        .frame(width: 400)
    }

    private var sessionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let error = sessions.listenerError {
                Text("Nie udało się uruchomić odbiornika: \(error)")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            ConnectionBanner(model: container.claudeCode, actions: container.claudeCodeActions)
            if let message = sessions.jumpMessage {
                HStack(alignment: .top) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        actions.dismissJumpMessage()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Divider()
            if sessions.sessions.isEmpty {
                EmptySessions(connection: container.claudeCode.connection)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(sessions.sessions) { session in
                            SessionRow(session: session) { actions.select(session) }
                        }
                    }
                }
                .frame(height: min(CGFloat(sessions.sessions.count) * 60, 420))
            }
            if !container.usage.isEmpty {
                Divider()
                UsageSection(model: container.usage, actions: container.usageActions)
            }
            Divider()
            footer
        }
        .onAppear { container.claudeCodeActions.refreshConnection() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tendbar").font(.headline)
            Spacer()
            StateCount(state: .working, count: sessions.count(of: .working))
            StateCount(state: .needsYou, count: sessions.count(of: .needsYou))
            StateCount(state: .done, count: sessions.count(of: .done))
        }
    }

    private var footer: some View {
        HStack {
            Button("Oznacz jako przeczytane") { actions.markAllAsRead() }
                .disabled(!sessions.hasUnread)
            Spacer()
            Button {
                dismiss()
                NSApp.activate()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Ustawienia (⌘,)")
            Menu {
                Button("Usuń zakończone sesje") { actions.removeEndedSessions() }
                Button("Pokaż log zdarzeń") { container.systemActions.revealEventLog() }
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
    let model: ClaudeCodeViewModel
    let actions: ClaudeCodeController

    var body: some View {
        if let error = model.connectionError {
            banner(Text("Nie udało się zmienić ustawień Claude Code: \(error)"), color: .red, button: false)
        } else if model.connection == .disconnected {
            banner(Text("Tendbar nie jest połączony z Claude Code"), color: .secondary, button: true)
        } else if model.connection == .outdated {
            banner(Text("Hooki Tendbara są nieaktualne albo niepełne"), color: .secondary, button: true)
        } else if !model.helperAvailable {
            banner(Text("Nie znaleziono pomocnika tendbar-hook w aplikacji"), color: .red, button: false)
        }
    }

    private func banner(_ text: Text, color: Color, button: Bool) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(color)
            text.font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if button {
                Button("Połącz") { actions.connect() }
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

struct StateMark: View {
    let state: SessionState
    let unread: Bool

    var body: some View {
        Group {
            switch state {
            case .working:
                Circle().strokeBorder(state.color, lineWidth: 1.5)
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

struct EmptySessions: View {
    let connection: HookConnection?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Żadna sesja nie jest uruchomiona").fontWeight(.medium)
                Text("Sesje pojawią się tu same, gdy uruchomisz Claude Code w terminalu")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text("claude")
                    .font(.system(.callout, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("claude", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Kopiuj polecenie")
                .accessibilityLabel("Kopiuj polecenie claude")
            }
            HStack(spacing: 8) {
                Circle().fill(connection == .connected ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(connection == .connected ? "Połączono z Claude Code" : "Nie połączono z Claude Code")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
