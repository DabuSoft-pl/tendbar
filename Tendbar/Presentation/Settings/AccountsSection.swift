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
                    Text("No profiles yet. The default ~/.claude profile appears after the first session")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.profiles) { profile in
                    ProfileRow(profile: profile, actions: actions)
                }
            } header: {
                Text("Claude Code profiles")
            } footer: {
                Text("An account's limits come from Claude Code sessions signed in to it")
            }
            Section {
                HStack {
                    TextField("Name or e-mail", text: $newName)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(slug.isEmpty)
                }
                if let error = model.profileError {
                    Text(error).foregroundStyle(.red)
                }
            } header: {
                Text("New profile")
            } footer: {
                Text(slug.isEmpty
                    ? String(localized: "A profile is a separate Claude Code directory you sign in to with /login")
                    : String(localized: "Creates ~/.claude-\(slug)"))
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
                Text(profile.email ?? String(localized: "not signed in"))
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
                    .help("Connected")
                    .accessibilityLabel("Connected")
            case .outdated, .disconnected:
                Button("Connect") { actions.connect(profile) }
            case nil:
                EmptyView()
            }
            Menu {
                Button("Copy command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(profile.launchCommand, forType: .string)
                }
                if profile.directory != nil {
                    Button("Remove from the list (keeps the directory)") { actions.remove(profile) }
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
