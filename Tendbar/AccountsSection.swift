import AppKit
import SwiftUI
import TendbarKit

struct AccountsSection: View {
    let model: AppModel
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.profiles) { profile in
                ProfileRow(model: model, profile: profile)
            }
            HStack {
                TextField("nazwa, np. praca", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Dodaj konto", action: add)
                    .disabled(newName.isEmpty)
            }
            if let error = model.profileError {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text("Nowe konto dostaje własny katalog ~/.claude-<nazwa> ze wspólnymi ustawieniami, CLAUDE.md, agentami, skillami i pluginami. Uruchom w nim Claude poleceniem z listy i zaloguj się na drugie konto przez /login.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        model.addProfile(named: name)
        if model.profileError == nil { newName = "" }
    }
}

private struct ProfileRow: View {
    let model: AppModel
    let profile: AppModel.Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(profile.email ?? String(localized: "niezalogowane"))
                    .fontWeight(.semibold)
                    .foregroundStyle(profile.email == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                switch profile.connection {
                case .connected:
                    Label("połączone", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                case .outdated, .disconnected:
                    Button("Połącz") { model.connect(profile) }
                        .controlSize(.small)
                case nil:
                    EmptyView()
                }
            }
            HStack(spacing: 6) {
                Text(profile.launchCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(profile.launchCommand, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Kopiuj polecenie")
                Spacer()
                if profile.directory != nil {
                    Button {
                        model.removeProfile(profile)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Usuń z listy (katalog zostaje)")
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
