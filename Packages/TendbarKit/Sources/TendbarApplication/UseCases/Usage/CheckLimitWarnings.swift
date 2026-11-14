import TendbarDomain

/// Warns once per window when an account crosses 80% or 90%; flashes the screen at 90%.
@MainActor
public final class CheckLimitWarnings {
    public static let rememberedLimit = 200

    private let usage: UsageRepository
    private let fired: FiredWarningRepository
    private let alerts: AlertPresenting
    private let flasher: ScreenFlashing
    private let settings: AlertSettingsProviding
    private let clock: Clock

    public init(
        usage: UsageRepository,
        fired: FiredWarningRepository,
        alerts: AlertPresenting,
        flasher: ScreenFlashing,
        settings: AlertSettingsProviding,
        clock: Clock
    ) {
        self.usage = usage
        self.fired = fired
        self.alerts = alerts
        self.flasher = flasher
        self.settings = settings
        self.clock = clock
    }

    public func execute() {
        let now = clock.now()
        var keys = fired.load()
        var warnings: [(AccountUsage, LimitWarning)] = []
        for account in usage.load().ordered {
            for warning in LimitWarnings.pending(for: account, now: now, fired: keys) {
                warnings.append((account, warning))
                keys.formUnion(LimitWarnings.keys(firing: warning))
            }
        }
        guard !warnings.isEmpty else { return }
        fired.save(Set(keys.sorted().suffix(Self.rememberedLimit)))

        let settings = settings.alertSettings
        guard settings.notifyLimits else { return }
        for (account, warning) in warnings {
            alerts.presentLimit(warning, account: account, sound: settings.alertSound)
        }
        if settings.glows, warnings.contains(where: { $0.1.threshold >= 90 }) {
            flasher.flash(.attention)
        }
    }

    /// Announces windows that warned before and have reset since. Runs on a timer, since a reset brings no reading.
    public func checkResets() {
        let now = clock.now()
        var keys = fired.load()
        var resets: [(AccountUsage, LimitReset)] = []
        for account in usage.load().ordered {
            for reset in LimitWarnings.resets(for: account, now: now, fired: keys) {
                resets.append((account, reset))
                keys.insert(LimitWarnings.resetKey(accountID: reset.accountID, window: reset.window, resetsAt: reset.resetsAt))
            }
        }
        guard !resets.isEmpty else { return }
        fired.save(Set(keys.sorted().suffix(Self.rememberedLimit)))

        let settings = settings.alertSettings
        guard settings.notifyLimits, settings.notifyLimitResets else { return }
        for (account, reset) in resets {
            alerts.presentLimitReset(reset, account: account, sound: settings.alertSound)
        }
    }
}
