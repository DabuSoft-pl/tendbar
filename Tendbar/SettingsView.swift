import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            NotificationSettings(model: model)
                .tabItem { Label("Powiadomienia", systemImage: "bell") }
            AccountsSection(model: model)
                .tabItem { Label("Konta", systemImage: "person.2") }
            GeneralSettings(model: model)
                .tabItem { Label("Ogólne", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 460)
        .onAppear { model.refresh() }
    }
}

private struct NotificationSettings: View {
    let model: AppModel

    var body: some View {
        @Bindable var preferences = model.preferences
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
                        Button("Pokaż") { model.previewGlow() }
                    }
                }
            } footer: {
                Text("Ramka mignie, gdy sesja czeka, po błędzie i przy 90% limitu")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Uprawnienia") {
                    HStack {
                        Text(statusText).foregroundStyle(.secondary)
                        Button("Wyślij testowe") { model.sendTestNotification() }
                    }
                }
                if model.notificationStatus == .denied {
                    LabeledContent("Wyłączone w systemie") {
                        Button("Otwórz Ustawienia systemowe") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                if let error = model.notificationError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch model.notificationStatus {
        case .authorized, .provisional, .ephemeral: String(localized: "przyznane")
        case .denied: String(localized: "odmowa")
        case .notDetermined: String(localized: "jeszcze nie przyznane")
        @unknown default: String(localized: "nieznane")
        }
    }
}

private struct GeneralSettings: View {
    let model: AppModel

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section {
                Toggle("Uruchamiaj przy logowaniu", isOn: Binding(
                    get: { model.launchAtLogin == .enabled || model.launchAtLogin == .requiresApproval },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle(NotchController.hasNotch ? "Stan sesji w notchu" : "Stan sesji na środku paska menu", isOn: $preferences.notchView)
                    .onChange(of: preferences.notchView) { model.refreshNotch() }
            } footer: {
                if model.launchAtLogin == .requiresApproval {
                    Text("Zatwierdź Tendbar w Ustawieniach systemowych → Ogólne → Rzeczy otwierane podczas logowania")
                        .foregroundStyle(.secondary)
                } else if let error = model.launchAtLoginError {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section {
                LabeledContent("Hooki w ~/.claude") {
                    HStack {
                        Text(connectionText).foregroundStyle(.secondary)
                        switch model.connection {
                        case .connected, .outdated:
                            Button("Rozłącz") { model.disconnect() }
                        case .disconnected:
                            Button("Połącz") { model.connect() }
                        case nil:
                            EmptyView()
                        }
                    }
                }
            } header: {
                Text("Claude Code")
            } footer: {
                if let error = model.connectionError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                } else {
                    Text("Połączenie dopisuje hooki Tendbara i opakowuje statusLine. Przed zmianą powstaje kopia settings.json")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var connectionText: String {
        switch model.connection {
        case .connected: String(localized: "połączone")
        case .outdated: String(localized: "do aktualizacji")
        case .disconnected: String(localized: "niepołączone")
        case nil: String(localized: "brak tendbar-hook")
        }
    }
}
