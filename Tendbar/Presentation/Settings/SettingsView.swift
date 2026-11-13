import AppKit
import SwiftUI
import TendbarApplication

private enum SettingsPage: String, CaseIterable, Identifiable {
    case claudeCode, notifications, general

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .claudeCode: "Claude Code"
        case .notifications: "Notifications"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .claudeCode: "terminal"
        case .notifications: "bell"
        case .general: "gearshape"
        }
    }
}

struct SettingsView: View {
    let container: AppContainer
    @State private var page: SettingsPage = .claudeCode

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 700, height: 500)
        .onAppear(perform: refresh)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                Text("Tendbar").font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 16)
            ForEach(SettingsPage.allCases) { item in
                Button { page = item } label: {
                    Label(item.title, systemImage: item.symbol)
                        .labelStyle(SidebarLabelStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(page == item ? Color.primary.opacity(0.08) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(page == item ? .primary : .secondary)
                .accessibilityAddTraits(page == item ? .isSelected : [])
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Button("Data folder") { container.systemActions.revealDataFolder() }
                Text(Self.version)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .buttonStyle(.link)
            .font(.caption)
            .padding(.horizontal, 6)
        }
        .padding(12)
        .frame(width: 188)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .claudeCode:
            ClaudeCodeSettings(model: container.claudeCode, actions: container.claudeCodeActions)
        case .notifications:
            NotificationSettings(preferences: container.preferences, model: container.system, actions: container.systemActions)
        case .general:
            GeneralSettings(preferences: container.preferences, system: container.system, systemActions: container.systemActions)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return String(localized: "Version \(short) (\(build))")
    }

    private func refresh() {
        container.claudeCodeActions.refresh()
        container.systemActions.refresh()
    }
}

private struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.frame(width: 18)
            configuration.title
        }
        .font(.system(size: 13, weight: .medium))
    }
}

private struct ClaudeCodeSettings: View {
    let model: ClaudeCodeViewModel
    let actions: ClaudeCodeController

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    switch model.connection {
                    case .connected, .outdated:
                        Button("Disconnect") { actions.disconnect() }
                    case .disconnected:
                        Button("Connect") { actions.connect() }
                            .buttonStyle(.borderedProminent)
                    case nil:
                        EmptyView()
                    }
                } label: {
                    HStack(spacing: 10) {
                        StatusDot(color: model.connection == .connected ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connectionText)
                            Text("Hooks in ~/.claude/settings.json")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                if let error = model.connectionError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                } else {
                    Text("settings.json is backed up before every change")
                }
            }
            AccountsSection(model: model, actions: actions)
        }
        .formStyle(.grouped)
    }

    private var connectionText: String {
        switch model.connection {
        case .connected: String(localized: "Connected to Claude Code")
        case .outdated: String(localized: "Connection needs an update")
        case .disconnected: String(localized: "Not connected")
        case nil: String(localized: "tendbar-hook missing")
        }
    }
}

private struct NotificationSettings: View {
    @Bindable var preferences: Preferences
    let model: SystemViewModel
    let actions: SystemController

    var body: some View {
        Form {
            Section("Notify when") {
                Toggle("A session waits for you", isOn: $preferences.notifyNeedsYou)
                Toggle("A session finishes", isOn: $preferences.notifyDone)
                Toggle("A turn fails", isOn: $preferences.notifyFailed)
                Toggle("An account passes 80% and 90% of a limit", isOn: $preferences.notifyLimits)
            }
            Section {
                Toggle("Sound", isOn: $preferences.playSound)
                Toggle("Start of the reply in “Done” notifications", isOn: $preferences.showReplyPreview)
                    .disabled(!preferences.notifyDone)
                Toggle("Glowing screen edge", isOn: $preferences.edgeGlow)
                Toggle("Glow when a session finishes too", isOn: $preferences.glowOnDone)
                    .disabled(!preferences.edgeGlow)
                LabeledContent {
                    HStack {
                        Button("Preview glow") { actions.showFlash() }
                        Button("Test notification") { actions.sendTestNotification() }
                    }
                } label: {
                    Text("Try it")
                }
            } header: {
                Text("How")
            } footer: {
                Text("The edge glows orange when a session waits, green when it finishes, red after an error and at 90% of a limit")
            }
            if !granted || model.notificationError != nil {
                Section {
                    if !granted {
                        LabeledContent {
                            HStack {
                                if model.notificationPermission == .notDetermined {
                                    Button("Ask for permission") { actions.requestNotifications() }
                                }
                                Button("System Settings") { actions.openNotificationSettings() }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                StatusDot(color: .orange)
                                Text(model.notificationPermission == .notDetermined
                                    ? String(localized: "macOS has not asked for permission yet")
                                    : String(localized: "Notifications are turned off in macOS"))
                            }
                        }
                    }
                    if let error = model.notificationError {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            actions.refresh()
        }
    }

    private var granted: Bool {
        model.notificationPermission == .authorized
    }

}

private struct GeneralSettings: View {
    @Bindable var preferences: Preferences
    let system: SystemViewModel
    let systemActions: SystemController
    @State private var language = AppLanguage.current

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { system.loginItem != .disabled },
                    set: { systemActions.setLaunchAtLogin($0) }
                ))
                Toggle(NotchController.hasNotch ? "Session state next to the notch" : "Session state in the middle of the menu bar", isOn: $preferences.notchView)
                Toggle(isOn: $preferences.logEvents) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Event log")
                            Text("For troubleshooting. Turning it off deletes the log")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if preferences.logEvents {
                            Button("Show") { systemActions.revealEventLog() }
                        }
                    }
                }
            } footer: {
                if system.loginItem == .requiresApproval {
                    Text("Allow Tendbar in System Settings → General → Login Items")
                        .foregroundStyle(.secondary)
                } else if let error = system.loginItemError {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Everything stays on this Mac. Tendbar sends nothing over the network")
                }
            }
            Section {
                Picker("Language", selection: $language) {
                    Text("System").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "Polski").tag(AppLanguage.polish)
                }
                .onChange(of: language) { language.apply() }
                if language != AppLanguage.launched {
                    LabeledContent("Takes effect after a restart") {
                        Button("Restart Tendbar") { AppLanguage.relaunch() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
    }
}
