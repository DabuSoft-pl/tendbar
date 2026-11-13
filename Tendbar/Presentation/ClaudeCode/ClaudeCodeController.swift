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

    func refreshConnection() {
        do {
            model.connection = try checkConnection.execute()
            model.helperAvailable = model.connection != nil
            model.connectionError = nil
        } catch {
            model.connectionError = String(describing: error)
        }
    }

    func connect() {
        change(.connect)
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
            model.profileError = String(localized: "Nazwa może mieć 1–32 znaki: małe litery, cyfry i myślniki.")
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
