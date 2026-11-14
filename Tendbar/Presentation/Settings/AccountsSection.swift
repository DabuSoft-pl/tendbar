import AppKit
import SwiftUI
import TendbarApplication
import TendbarDomain

struct AccountsSection: View {
    let model: ClaudeCodeViewModel
    let actions: ClaudeCodeController
    @State private var newName = ""
    @State private var adding = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Section {
            if model.profiles.isEmpty {
                Text("No profiles yet. The default ~/.claude profile appears after the first session")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.profiles) { profile in
                ProfileRow(profile: profile, actions: actions)
            }
            if adding {
                HStack {
                    TextField("Name or e-mail", text: $newName)
                        .focused($nameFocused)
                        .onSubmit(add)
                    Button("Cancel") { stopAdding() }
                        .keyboardShortcut(.cancelAction)
                    Button("Add", action: add)
                        .disabled(slug.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                .focusedSceneValue(\.editingInPlace, true)
            } else {
                Button {
                    adding = true
                    nameFocused = true
                } label: {
                    Label("Add profile", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            if let error = model.profileError {
                Text(error).foregroundStyle(Palette.vermilion)
            }
        } header: {
            Text("Claude Code profiles")
        } footer: {
            if adding {
                Text(slug.isEmpty
                    ? String(localized: "A profile is a separate Claude Code directory you sign in to with /login")
                    : String(localized: "Creates ~/.claude-\(slug)"))
            } else {
                Text("An account's limits come from Claude Code sessions signed in to it")
            }
        }
    }

    private var slug: String {
        ProfileName.slug(from: newName)
    }

    private func add() {
        guard !slug.isEmpty else { return }
        actions.addProfile(named: slug)
        if model.profileError == nil { stopAdding() }
    }

    private func stopAdding() {
        newName = ""
        adding = false
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
                HStack(spacing: 6) {
                    StatusDot(color: Palette.sage)
                    Text("Hooks on").foregroundStyle(.secondary)
                }
                .font(.callout)
                .help("Tendbar's hooks are in this profile's settings.json")
            case .outdated, .otherCopy, .helperGone, .disconnected:
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
