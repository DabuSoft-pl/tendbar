import AppKit
import SwiftUI
import TendbarApplication

struct SettingsView: View {
    let container: AppContainer

    var body: some View {
        TabView {
            NotificationSettings(preferences: container.preferences, model: container.system, actions: container.systemActions)
                .frame(height: 540)
                .tabItem { Label("Powiadomienia", systemImage: "bell") }
            AccountsSection(model: container.claudeCode, actions: container.claudeCodeActions)
                .frame(height: 420)
                .tabItem { Label("Konta", systemImage: "person.2") }
            GeneralSettings(
                preferences: container.preferences,
                claudeCode: container.claudeCode,
                claudeCodeActions: container.claudeCodeActions,
                system: container.system,
                systemActions: container.systemActions
            )
                .frame(height: 460)
                .tabItem { Label("Ogólne", systemImage: "gearshape") }
        }
        .frame(width: 520)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        container.claudeCodeActions.refresh()
        container.systemActions.refresh()
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
                Toggle(isOn: $preferences.edgeGlow) {
                    HStack {
                        Text("Świecąca ramka ekranu")
                        Spacer()
                        Button("Pokaż") { actions.showFlash() }
                    }
                }
                Toggle("Ramka także po skończonej pracy", isOn: $preferences.glowOnDone)
                    .disabled(!preferences.edgeGlow)
            } footer: {
                Text("Ramka mignie, gdy sesja czeka (pomarańczowa), skończy (zielona), po błędzie (czerwona) i przy 90% limitu")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Uprawnienia") {
                    HStack(spacing: 8) {
                        StatusDot(color: granted ? .green : .orange)
                        Text(statusText).foregroundStyle(.secondary)
                        Button("Wyślij testowe") { actions.sendTestNotification() }
                    }
                }
                if !granted {
                    LabeledContent(model.notificationPermission == .notDetermined
                        ? String(localized: "macOS jeszcze nie zapytał o zgodę")
                        : String(localized: "Powiadomienia wyłączone w systemie")) {
                        HStack {
                            if model.notificationPermission == .notDetermined {
                                Button("Poproś o zgodę") { actions.requestNotifications() }
                            }
                            Button("Otwórz Ustawienia systemowe") { actions.openNotificationSettings() }
                        }
                    }
                }
                if let error = model.notificationError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
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

    private var statusText: String {
        switch model.notificationPermission {
        case .authorized: String(localized: "przyznane")
        case .denied: String(localized: "odmowa")
        case .notDetermined: String(localized: "jeszcze nie przyznane")
        }
    }
}

private struct GeneralSettings: View {
    @Bindable var preferences: Preferences
    let claudeCode: ClaudeCodeViewModel
    let claudeCodeActions: ClaudeCodeController
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
            } footer: {
                if system.loginItem == .requiresApproval {
                    Text("Zatwierdź Tendbar w Ustawieniach systemowych → Ogólne → Rzeczy otwierane podczas logowania")
                        .foregroundStyle(.secondary)
                } else if let error = system.loginItemError {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section {
                LabeledContent("Hooki w ~/.claude") {
                    HStack(spacing: 8) {
                        StatusDot(color: claudeCode.connection == .connected ? .green : .orange)
                        Text(connectionText).foregroundStyle(.secondary)
                        switch claudeCode.connection {
                        case .connected, .outdated:
                            Button("Rozłącz") { claudeCodeActions.disconnect() }
                        case .disconnected:
                            Button("Połącz") { claudeCodeActions.connect() }
                        case nil:
                            EmptyView()
                        }
                    }
                }
            } header: {
                Text("Claude Code")
            } footer: {
                if let error = claudeCode.connectionError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                } else {
                    Text("Połączenie dopisuje hooki Tendbara i opakowuje statusLine. Przed zmianą powstaje kopia settings.json")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Wersja") {
                    Text(version).foregroundStyle(.secondary).monospacedDigit()
                }
                LabeledContent("Dane i log zdarzeń") {
                    HStack {
                        Button("Pokaż log") { systemActions.revealEventLog() }
                        Button("Pokaż folder") { systemActions.revealDataFolder() }
                    }
                }
            } header: {
                Text("O Tendbarze")
            } footer: {
                Text("Wszystko zostaje na tym Macu. Tendbar nie wysyła nic do sieci")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private var connectionText: String {
        switch claudeCode.connection {
        case .connected: String(localized: "połączone")
        case .outdated: String(localized: "do aktualizacji")
        case .disconnected: String(localized: "niepołączone")
        case nil: String(localized: "brak tendbar-hook")
        }
    }
}

private struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
    }
}
