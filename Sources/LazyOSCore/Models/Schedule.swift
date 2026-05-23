import Foundation

/// A simple recurring window when a service should be running.
/// Implemented as two launchd plists per service: one start (at `startCron`),
/// one stop (at `stopCron`). We keep our cron grammar minimal — exactly the
/// subset launchd can model: minute / hour / day-of-month / month / day-of-week.
public struct Schedule: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var startCron: String   // e.g. "0 9 * * 1-5"
    public var stopCron: String    // e.g. "0 19 * * 1-5"

    public init(enabled: Bool, startCron: String, stopCron: String) {
        self.enabled = enabled
        self.startCron = startCron
        self.stopCron = stopCron
    }

    public static let weekdays9to7 = Schedule(enabled: true, startCron: "0 9 * * 1-5", stopCron: "0 19 * * 1-5")
    public static let weekendsAlways = Schedule(enabled: true, startCron: "0 0 * * 6,0", stopCron: "59 23 * * 6,0")
    public static let evenings = Schedule(enabled: true, startCron: "0 18 * * *", stopCron: "0 23 * * *")
}
