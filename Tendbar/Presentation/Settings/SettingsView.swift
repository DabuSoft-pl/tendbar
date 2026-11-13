import AppKit
import SwiftUI
import TendbarApplication

private enum SettingsPage: String, CaseIterable, Identifiable {
    case claudeCode, notifications, general

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .claudeCode: "Claude Code"
        case .notifications: "Powiadomienia"
        case .general: "Ogólne"
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
                Button("Folder danych") { container.systemActions.revealDataFolder() }
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
        return String(localized: "Wersja \(short) (\(build))")
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
                        Button("Rozłącz") { actions.disconnect() }
                    case .disconnected:
                        Button("Połącz") { actions.connect() }
                            .buttonStyle(.borderedProminent)
                    case nil:
                        EmptyView()
                    }
                } label: {
                    HStack(spacing: 10) {
                        StatusDot(color: model.connection == .connected ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connectionText)
                            Text("Hooki w ~/.claude/settings.json")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                if let error = model.connectionError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                } else {
                    Text("Przed każdą zmianą powstaje kopia settings.json")
                }
            }
            AccountsSection(model: model, actions: actions)
        }
        .formStyle(.grouped)
    }

    private var connectionText: String {
        switch model.connection {
        case .connected: String(localized: "Połączone z Claude Code")
        case .outdated: String(localized: "Połączenie do aktualizacji")
        case .disconnected: String(localized: "Niepołączone")
        case nil: String(localized: "Brak tendbar-hook")
        }
    }
}

private struct NotificationSettings: View {
    @Bindable var preferences: Preferences
    let model: SystemViewModel
    let actions: SystemController

    var body: some View {
        Form {
            Section("Powiadamiaj, gdy") {
                Toggle("Sesja czeka na Ciebie", isOn: $preferences.notifyNeedsYou)
                Toggle("Sesja skończy pracę", isOn: $preferences.notifyDone)
                Toggle("Tura zakończy się błędem", isOn: $preferences.notifyFailed)
                Toggle("Limit konta przekroczy 80% i 90%", isOn: $preferences.notifyLimits)
            }
            Section {
                Toggle("Dźwięk", isOn: $preferences.playSound)
                Toggle("Początek odpowiedzi w powiadomieniu „Gotowe”", isOn: $preferences.showReplyPreview)
                    .disabled(!preferences.notifyDone)
                Toggle("Świecąca ramka ekranu", isOn: $preferences.edgeGlow)
                Toggle("Ramka także po skończonej pracy", isOn: $preferences.glowOnDone)
                    .disabled(!preferences.edgeGlow)
                LabeledContent {
                    HStack {
                        Button("Podgląd ramki") { actions.showFlash() }
                        Button("Testowe powiadomienie") { actions.sendTestNotification() }
                    }
                } label: {
                    Text("Wypróbuj")
                }
            } header: {
                Text("Jak")
            } footer: {
                Text("Ramka jest pomarańczowa, gdy sesja czeka, zielona po skończeniu, czerwona po błędzie i przy 90% limitu")
            }
            if !granted || model.notificationError != nil {
                Section {
                    if !granted {
                        LabeledContent {
                            HStack {
                                if model.notificationPermission == .notDetermined {
                                    Button("Poproś o zgodę") { actions.requestNotifications() }
                                }
                                Button("Ustawienia systemowe") { actions.openNotificationSettings() }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                StatusDot(color: .orange)
                                Text(model.notificationPermission == .notDetermined
                                    ? String(localized: "macOS jeszcze nie zapytał o zgodę")
                                    : String(localized: "Powiadomienia wyłączone w systemie"))
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

    var body: some View {
        Form {
            Section {
                Toggle("Uruchamiaj przy logowaniu", isOn: Binding(
                    get: { system.loginItem != .disabled },
                    set: { systemActions.setLaunchAtLogin($0) }
                ))
                Toggle(NotchController.hasNotch ? "Stan sesji w notchu" : "Stan sesji na środku paska menu", isOn: $preferences.notchView)
                Toggle(isOn: $preferences.logEvents) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Log zdarzeń")
                            Text("Do diagnozy problemów. Wyłączenie usuwa log")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if preferences.logEvents {
                            Button("Pokaż") { systemActions.revealEventLog() }
                        }
                    }
                }
            } footer: {
                if system.loginItem == .requiresApproval {
                    Text("Zatwierdź Tendbar w Ustawieniach systemowych → Ogólne → Rzeczy otwierane podczas logowania")
                        .foregroundStyle(.secondary)
                } else if let error = system.loginItemError {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Wszystko zostaje na tym Macu. Tendbar nie wysyła nic do sieci")
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
