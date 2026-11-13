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
            alerts.presentLimit(warning, account: account, sound: settings.sound)
        }
        if settings.flash, warnings.contains(where: { $0.1.threshold >= 90 }) {
            flasher.flash(.attention)
        }
    }
}
