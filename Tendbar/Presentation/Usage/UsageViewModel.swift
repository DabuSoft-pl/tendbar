import Foundation
import Observation
import TendbarApplication
import TendbarDomain

@MainActor
@Observable
final class UsageViewModel: UsageOutput {
    private(set) var store = UsageStore()
    /// The time the figures are read at. A limit drops to 0 when it resets with no new reading, so the app's timer
    /// moves this on and the menu bar and the pill follow; Observation does not see the clock by itself.
    private(set) var now = Date()

    var isEmpty: Bool { store.accounts.isEmpty }
    var accounts: [AccountUsage] { store.currentFirst }
    var currentAccountID: String? { store.current?.id }
    var currentLimit: Double { store.currentLimit(at: now) }
    /// The current account's five-hour and weekly usage, nil when not read yet.

    func isCurrent(_ account: AccountUsage) -> Bool {
        account.id == currentAccountID
    }

    func show(_ usage: UsageStore) {
        store = usage
        now = Date()
    }

    func tick(at date: Date = Date()) {
        now = date
    }
}
