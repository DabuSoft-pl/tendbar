import TendbarApplication

/// Builds the Claude Code feature: connecting the hooks and the `CLAUDE_CONFIG_DIR` profiles.
@MainActor
struct ClaudeCodeAssembly {
    let controller: ClaudeCodeController

    init(_ a: AppContainer.Adapters, model: ClaudeCodeViewModel) {
        controller = ClaudeCodeController(
            model: model,
            checkConnection: CheckHookConnection(connector: a.connector),
            changeConnection: ChangeHookConnection(connector: a.connector),
            listProfiles: ListProfiles(repository: a.profiles, emails: a.emails, connector: a.connector),
            addProfile: AddProfile(repository: a.profiles, directories: a.profileDirectories),
            removeProfile: RemoveProfile(repository: a.profiles)
        )
    }
}
