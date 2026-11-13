import Foundation
import Observation
import TendbarApplication
import TendbarDomain

@MainActor
@Observable
final class UsageViewModel: UsageOutput {
    private(set) var store = UsageStore()

    var isEmpty: Bool { store.accounts.isEmpty }
    var accounts: [AccountUsage] { store.currentFirst }
    var currentAccountID: String? { store.current?.id }
    var currentLimit: Double { store.currentLimit(at: Date()) }
    /// The current account's five-hour and weekly usage, nil when not read yet.
    var currentFiveHour: Double? { store.current?.fiveHour?.percentage(at: Date()) }
    var currentSevenDay: Double? { store.current?.sevenDay?.percentage(at: Date()) }

    func isCurrent(_ account: AccountUsage) -> Bool {
        account.id == currentAccountID
    }

    func show(_ usage: UsageStore) {
        store = usage
    }
}
