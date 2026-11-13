import AppKit
import SwiftUI
import TendbarKit

struct AccountsSection: View {
    let model: AppModel
    @State private var newName = ""

    var body: some View {
        Form {
            if FileManager.default.fileExists(atPath: ClaudeSwapUsage.defaultURL.path) {
                Section {
                    Label("Limity wszystkich kont cswap Tendbar czyta z jego pamięci podręcznej", systemImage: "arrow.triangle.2.circlepath")
                } footer: {
                    Text("Przy cswap osobne profile nie są potrzebne")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Profile Claude Code") {
                ForEach(model.profiles) { profile in
                    ProfileRow(model: model, profile: profile)
                }
            }
            Section {
                HStack {
                    TextField("Nazwa lub e-mail", text: $newName)
                        .onSubmit(add)
                    Button("Dodaj", action: add)
                        .disabled(slug.isEmpty)
                }
                if let error = model.profileError {
                    Text(error).foregroundStyle(.red)
                }
            } header: {
                Text("Nowy profil")
            } footer: {
                Text(slug.isEmpty
                    ? String(localized: "Profil to osobny katalog Claude Code. Logujesz się w nim poleceniem /login. Ustawienia, CLAUDE.md, agenci, skille i pluginy są wspólne z ~/.claude.")
                    : String(localized: "Powstanie katalog ~/.claude-\(slug)"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var slug: String {
        ClaudeProfiles.slug(from: newName)
    }

    private func add() {
        guard !slug.isEmpty else { return }
        model.addProfile(named: slug)
        if model.profileError == nil { newName = "" }
    }
}

private struct ProfileRow: View {
    let model: AppModel
    let profile: AppModel.Profile

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.email ?? String(localized: "niezalogowane"))
                    .foregroundStyle(profile.email == nil ? .secondary : .primary)
                    .lineLimit(1)
                Text(profile.launchCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            switch profile.connection {
            case .connected:
                Text("połączone").foregroundStyle(.secondary)
            case .outdated, .disconnected:
                Button("Połącz") { model.connect(profile) }
            case nil:
                EmptyView()
            }
            Menu {
                Button("Kopiuj polecenie") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(profile.launchCommand, forType: .string)
                }
                if profile.directory != nil {
                    Button("Usuń z listy (katalog zostaje)") { model.removeProfile(profile) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}
