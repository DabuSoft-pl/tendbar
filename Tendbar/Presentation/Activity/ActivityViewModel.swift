import Foundation
import Observation
import TendbarApplication
import TendbarDomain

/// Day by day turns and waits. Use cases push new numbers here through `ActivityOutput`.
@MainActor
@Observable
final class ActivityViewModel: ActivityOutput {
    private(set) var stats = ActivityStats()

    func today(now: Date = Date(), calendar: Calendar = .current) -> DayActivity {
        stats.day(of: now, calendar: calendar)
    }

    func show(_ activity: ActivityStats) {
        stats = activity
    }
}
