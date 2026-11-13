import AppKit
import ServiceManagement
import SwiftUI

struct SettingsPanel: View {
    let model: AppModel
    let onClose: () -> Void

    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onClose) {
                    Label("Wróć", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("Ustawienia").font(.headline)
            }

            section("Powiadomienia") {
                Toggle("Gdy sesja czeka na Ciebie", isOn: $preferences.notifyNeedsYou)
                Toggle("Gdy sesja skończy pracę", isOn: $preferences.notifyDone)
                Toggle("Gdy tura zakończy się błędem", isOn: $preferences.notifyFailed)
                Toggle("Dźwięk", isOn: $preferences.playSound)
                if model.notificationStatus == .denied {
                    HStack {
                        Text("Powiadomienia Tendbara są wyłączone w Ustawieniach systemowych.")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Otwórz") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                    .font(.callout)
                }
            }

            section("Ogólne") {
                Toggle("Uruchamiaj przy logowaniu", isOn: Binding(
                    get: { model.launchAtLogin == .enabled || model.launchAtLogin == .requiresApproval },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if model.launchAtLogin == .requiresApproval {
                    Text("Zatwierdź Tendbar w Ustawieniach systemowych → Ogólne → Rzeczy otwierane podczas logowania.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = model.launchAtLoginError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                HStack {
                    Text(connectionText).foregroundStyle(.secondary)
                    Spacer()
                    if model.connection == .connected || model.connection == .outdated {
                        Button("Rozłącz") { model.disconnect() }.controlSize(.small)
                    } else if model.connection == .disconnected {
                        Button("Połącz") { model.connect() }.controlSize(.small)
                    }
                }
                .font(.callout)
            }

            section("Sesje") {
                Button("Usuń zakończone sesje") { model.removeEnded() }
                    .controlSize(.small)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear { model.refresh() }
    }

    private var connectionText: String {
        switch model.connection {
        case .connected: String(localized: "Połączono z Claude Code")
        case .outdated: String(localized: "Hooki wymagają aktualizacji")
        case .disconnected: String(localized: "Nie połączono z Claude Code")
        case nil: String(localized: "Brak pomocnika tendbar-hook")
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            content()
        }
    }
}
