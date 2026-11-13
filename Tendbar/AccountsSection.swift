import AppKit
import SwiftUI
import TendbarKit

struct AccountsSection: View {
    let model: AppModel
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if FileManager.default.fileExists(atPath: ClaudeSwapUsage.defaultURL.path) {
                Label("Wykryto cswap: limity wszystkich jego kont Tendbar czyta z jego pamięci podręcznej. Osobne profile poniżej nie są wtedy potrzebne.", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.profiles) { profile in
                ProfileRow(model: model, profile: profile)
            }
            HStack {
                TextField("nazwa lub e-mail drugiego konta", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Dodaj konto", action: add)
                    .disabled(slug.isEmpty)
            }
            if !slug.isEmpty {
                Text("Powstanie katalog ~/.claude-\(slug)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let error = model.profileError {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text("Wpisana nazwa służy tylko do nazwania katalogu. Na konto logujesz się w Claude: uruchom polecenie z listy w terminalu i wpisz /login. Profil współdzieli z ~/.claude ustawienia, CLAUDE.md, agentów, skille i pluginy.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
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
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(profile.email ?? String(localized: "niezalogowane"))
                    .fontWeight(.medium)
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
