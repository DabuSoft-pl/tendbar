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
    @AppStorage("panel.showsEarlier") private var showsEarlier = false
    @State private var listHeight: CGFloat = 0
    @State private var selection: String?
    @FocusState private var focused: Bool

    var body: some View {
        sessionsPanel
        .padding(16)
        .frame(width: 400)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.return) { openSelection() }
        .onAppear {
            selection = nil
            focused = true
        }
        .fitsWindow()
    }

    private var current: [Session] { sessions.sessions.filter(\.isCurrent) }
    private var earlier: [Session] { sessions.sessions.filter { !$0.isCurrent } }
    private var showsAllEarlier: Bool { showsEarlier || current.isEmpty }

    /// The rows on screen, top to bottom, which the arrow keys walk through.
    private var visible: [Session] {
        current + (showsAllEarlier ? earlier : [])
    }

    private func move(by step: Int) -> KeyPress.Result {
        let rows = visible
        guard !rows.isEmpty else { return .ignored }
        let index = rows.firstIndex { $0.id == selection }.map { $0 + step } ?? (step > 0 ? 0 : rows.count - 1)
        selection = rows[min(max(index, 0), rows.count - 1)].id
        return .handled
    }

    private func openSelection() -> KeyPress.Result {
        guard let session = visible.first(where: { $0.id == selection }) else { return .ignored }
        actions.select(session)
        return .handled
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
                sessionList
            }
            if !container.usage.isEmpty, container.preferences.usageStyle != .hidden {
                Divider()
                UsageSection(model: container.usage, actions: container.usageActions, compact: container.preferences.usageStyle == .compact)
            }
            Divider()
            footer
        }
        .onAppear { container.claudeCodeActions.refreshConnection() }
    }

    /// Sessions that are busy, waiting or unread come first. Read and ended ones fold under "Earlier", and the list
    /// scrolls past a fixed height, so the panel never grows past the screen.
    private var sessionList: some View {
        let current = current
        let earlier = earlier
        let expanded = showsAllEarlier
        return ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(current) { row($0) }
                if !earlier.isEmpty {
                    if !current.isEmpty {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { showsEarlier.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .rotationEffect(.degrees(expanded ? 90 : 0))
                                Text("Earlier (\(earlier.count))")
                                Spacer()
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if expanded {
                        ForEach(earlier) { row($0) }
                            .transition(.opacity)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .onChange(of: selection) {
            if let selection { proxy.scrollTo(selection) }
        }
        }
        .frame(height: min(max(listHeight, 36), 320))
    }

    private func row(_ session: Session) -> some View {
        let preferences = container.preferences
        return SessionRow(
            session: session,
            showsDetail: preferences.panelPreviews,
            highlighted: selection == session.id,
            muted: preferences.isMuted(session.cwd),
            onHover: { if $0 { selection = session.id } },
            onToggleMute: { folder in preferences.setMuted(!preferences.isMuted(folder), folder: folder) }
        ) { actions.select(session) }
        .id(session.id)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tendbar").font(.headline)
            Spacer()
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// What is going on, in words, most urgent first: "1 waiting · 2 working".
    private var summary: String {
        let waiting = sessions.count(of: .needsYou)
        let failed = sessions.count(of: .failed)
        let working = sessions.count(of: .working)
        var parts: [String] = []
        if waiting > 0 { parts.append(String(localized: "\(waiting) waiting")) }
        if failed > 0 { parts.append(String(localized: "\(failed) with an error")) }
        if working > 0 { parts.append(String(localized: "\(working) working")) }
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack {
            if sessions.hasUnread {
                Button("Mark all as read") { actions.markAllAsRead() }
            }
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

struct SessionRow: View {
    let session: Session
    var showsDetail = true
    var highlighted = false
    var muted = false
    var onHover: (Bool) -> Void = { _ in }
    var onToggleMute: ((String) -> Void)?
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
                        if muted {
                            Image(systemName: "bell.slash")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .help("Notifications muted for this folder")
                                .accessibilityLabel("Muted")
                        }
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(session.timeText(now: context.date))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if showsDetail, session.state != .working {
                        Text(detail)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(highlighted ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .contextMenu {
            if let folder = session.cwd, let onToggleMute {
                Button(muted ? String(localized: "Unmute this folder") : String(localized: "Mute this folder")) {
                    onToggleMute(folder)
                }
            }
        }
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

private extension Session {
    /// Busy, waiting for you, or with something you have not read yet.
    var isCurrent: Bool {
        state == .working || state == .needsYou || unread
    }
}
