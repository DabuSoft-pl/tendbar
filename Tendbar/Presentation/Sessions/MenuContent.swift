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
                Text("Could not start the listener: \(error)")
                    .foregroundStyle(Palette.vermilion)
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
            StateCount(state: .needsYou, count: sessions.count(of: .needsYou))
            StateCount(state: .failed, count: sessions.count(of: .failed))
            StateCount(state: .done, count: sessions.count(of: .done))
            StateCount(state: .working, count: sessions.count(of: .working))
        }
    }

    private var footer: some View {
        HStack {
            Button("Mark all as read") { actions.markAllAsRead() }
                .disabled(!sessions.hasUnread)
            Spacer()
            Button {
                dismiss()
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
                DispatchQueue.main.async {
                    NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }?
                        .makeKeyAndOrderFront(nil)
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
            Menu {
                Button("Remove ended sessions") { actions.removeEndedSessions() }
                Divider()
                Button("Quit Tendbar") { NSApplication.shared.terminate(nil) }
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
            banner(Text("Could not change the Claude Code settings: \(error)"), color: Palette.vermilion, button: false)
        } else if model.connection == .disconnected {
            banner(Text("Tendbar is not connected to Claude Code"), color: .secondary, button: true)
        } else if model.connection == .outdated {
            banner(Text("Tendbar's hooks are outdated or incomplete"), color: .secondary, button: true)
        } else if !model.helperAvailable {
            banner(Text("The tendbar-hook helper is missing from the app"), color: Palette.vermilion, button: false)
        }
    }

    private func banner(_ text: Text, color: Color, button: Bool) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(color)
            text.font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if button {
                Button("Connect") { actions.connect() }
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
        if Date().timeIntervalSince(session.updatedAt) < 10 { return String(localized: "now") }
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
        .accessibilityLabel(unread && state == .done ? String(localized: "\(state.label), unread") : state.label)
    }
}

struct EmptySessions: View {
    let connection: HookConnection?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("No sessions running").fontWeight(.medium)
                Text("Sessions show up here once you start Claude Code in a terminal")
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
                .help("Copy command")
                .accessibilityLabel("Copy the claude command")
            }
            HStack(spacing: 8) {
                Circle().fill(connection == .connected ? Palette.sage : Palette.amber).frame(width: 8, height: 8)
                Text(connection == .connected ? "Connected to Claude Code" : "Not connected to Claude Code")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
