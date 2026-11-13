import TendbarApplication
import TendbarDomain

@MainActor
final class UsageController {
    private let forgetAccount: ForgetAccount

    init(forgetAccount: ForgetAccount) {
        self.forgetAccount = forgetAccount
    }

    func forget(_ account: AccountUsage) {
        forgetAccount.execute(accountID: account.id)
    }
}
