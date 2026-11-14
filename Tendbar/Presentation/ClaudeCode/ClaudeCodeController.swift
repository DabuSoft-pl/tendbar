import Foundation
import TendbarApplication

@MainActor
final class ClaudeCodeController {
    private let model: ClaudeCodeViewModel
    private let checkConnection: CheckHookConnection
    private let changeConnection: ChangeHookConnection
    private let listProfiles: ListProfiles
    private let addProfile: AddProfile
    private let removeProfile: RemoveProfile

    init(
        model: ClaudeCodeViewModel,
        checkConnection: CheckHookConnection,
        changeConnection: ChangeHookConnection,
        listProfiles: ListProfiles,
        addProfile: AddProfile,
        removeProfile: RemoveProfile
    ) {
        self.model = model
        self.checkConnection = checkConnection
        self.changeConnection = changeConnection
        self.listProfiles = listProfiles
        self.addProfile = addProfile
        self.removeProfile = removeProfile
    }

    func refresh() {
        refreshConnection()
        model.profiles = listProfiles.execute()
    }

    /// Assigns only what changed: the 30-second timer runs this, and every assignment to the observable model
    /// redraws the menu bar image.
    func refreshConnection() {
        do {
            let connection = try checkConnection.execute()
            if model.connection != connection { model.connection = connection }
            if model.helperAvailable != (connection != nil) { model.helperAvailable = connection != nil }
            if model.connectionError != nil { model.connectionError = nil }
        } catch {
            model.connectionError = String(describing: error)
        }
    }

    /// The default profile and every added one, without reading account emails again. Runs at launch, when the
    /// panel opens and with the app's 30-second timer, so a `settings.json` changed elsewhere shows up on its own.
    func refreshConnections() {
        refreshConnection()
        guard !model.profiles.isEmpty else {
            model.profiles = listProfiles.execute()
            return
        }
        let profiles = model.profiles.map { profile in
            var profile = profile
            profile.connection = (try? checkConnection.execute(configDirectory: profile.directory)) ?? nil
            return profile
        }
        if profiles != model.profiles { model.profiles = profiles }
    }

    func connect() {
        change(.connect)
    }

    /// Connects every profile that needs it, each with its own backup. Only from a click.
    func connectAll() {
        let profiles = model.needsConnect
        do {
            for profile in profiles {
                try changeConnection.execute(.connect, configDirectory: profile.directory)
            }
            model.connectionError = nil
        } catch {
            model.connectionError = String(describing: error)
        }
        refreshConnections()
    }

    func disconnect() {
        change(.disconnect)
    }

    func connect(_ profile: ProfileSummary) {
        do {
            try changeConnection.execute(.connect, configDirectory: profile.directory)
            model.profileError = nil
        } catch {
            model.profileError = String(describing: error)
        }
        refresh()
    }

    func addProfile(named name: String) {
        do {
            try addProfile.execute(name: name)
            model.profileError = nil
        } catch ProfileCreationError.invalidName {
            model.profileError = String(localized: "A name has 1–32 characters: lowercase letters, digits and hyphens.")
        } catch let ProfileCreationError.failed(message) {
            model.profileError = message
        } catch {
            model.profileError = error.localizedDescription
        }
        model.profiles = listProfiles.execute()
    }

    func remove(_ profile: ProfileSummary) {
        guard let directory = profile.directory else { return }
        removeProfile.execute(directory: directory)
        model.profiles = listProfiles.execute()
    }

    private func change(_ change: ChangeHookConnection.Change) {
        do {
            try changeConnection.execute(change)
            model.connectionError = nil
        } catch {
            model.connectionError = String(describing: error)
        }
        refreshConnection()
    }
}
