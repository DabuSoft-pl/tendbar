import AppKit
import SwiftUI
import TendbarApplication
import TendbarDomain

struct AccountsSection: View {
    let model: ClaudeCodeViewModel
    let actions: ClaudeCodeController
    @State private var newName = ""

    var body: some View {
        Group {
            Section {
                if model.profiles.isEmpty {
                    Text("Brak profili. Domyślny profil ~/.claude pojawi się po pierwszej sesji")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.profiles) { profile in
                    ProfileRow(profile: profile, actions: actions)
                }
            } header: {
                Text("Profile Claude Code")
            } footer: {
                Text("Limity konta przychodzą z sesji Claude Code zalogowanych na tym koncie")
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
                    ? String(localized: "Profil to osobny katalog Claude Code, w którym logujesz się przez /login")
                    : String(localized: "Powstanie katalog ~/.claude-\(slug)"))
            }
        }
    }

    private var slug: String {
        ProfileName.slug(from: newName)
    }

    private func add() {
        guard !slug.isEmpty else { return }
        actions.addProfile(named: slug)
        if model.profileError == nil { newName = "" }
    }
}

private struct ProfileRow: View {
    let profile: ProfileSummary
    let actions: ClaudeCodeController

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
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .help("Połączone")
                    .accessibilityLabel("Połączone")
            case .outdated, .disconnected:
                Button("Połącz") { actions.connect(profile) }
            case nil:
                EmptyView()
            }
            Menu {
                Button("Kopiuj polecenie") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(profile.launchCommand, forType: .string)
                }
                if profile.directory != nil {
                    Button("Usuń z listy (katalog zostaje)") { actions.remove(profile) }
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
