import Foundation

/// Parses a 5-field cron expression into a launchd `StartCalendarInterval`
/// dictionary and produces a plain-English description for the UI.
///
/// Supported grammar:
///   minute hour day-of-month month day-of-week
/// Each field is "*", a number, a list "a,b,c", or a range "a-b".
/// (No steps "*/n" — launchd doesn't support them anyway.)
public struct CronExpression: Equatable, Sendable {
    public var minute: [Int]?    // nil = any
    public var hour: [Int]?
    public var day: [Int]?
    public var month: [Int]?
    public var weekday: [Int]?   // 0=Sun ... 6=Sat (launchd uses Sun=0)

    public init(minute: [Int]? = nil, hour: [Int]? = nil, day: [Int]? = nil, month: [Int]? = nil, weekday: [Int]? = nil) {
        self.minute = minute; self.hour = hour; self.day = day; self.month = month; self.weekday = weekday
    }
}

public enum CronParser {
    public static func parse(_ expr: String) -> CronExpression? {
        let parts = expr.split(separator: " ").map(String.init)
        guard parts.count == 5 else { return nil }
        guard let m = field(parts[0], range: 0...59),
              let h = field(parts[1], range: 0...23),
              let d = field(parts[2], range: 1...31),
              let mo = field(parts[3], range: 1...12),
              let w = field(parts[4], range: 0...7) else { return nil }
        return CronExpression(
            minute: m, hour: h, day: d, month: mo,
            // launchd treats Sunday as 0 (or 7). Normalize 7 → 0.
            weekday: w?.map { $0 == 7 ? 0 : $0 }
        )
    }

    /// `[Int]?` outer optional: `nil` = field present but invalid. `Optional.some(nil)` = "*". Otherwise the values.
    private static func field(_ s: String, range: ClosedRange<Int>) -> [Int]?? {
        if s == "*" { return .some(nil) }
        var result: [Int] = []
        for chunk in s.split(separator: ",") {
            if let dash = chunk.firstIndex(of: "-") {
                let lo = Int(chunk[..<dash]) ?? -1
                let hi = Int(chunk[chunk.index(after: dash)...]) ?? -1
                guard range.contains(lo), range.contains(hi), lo <= hi else { return nil }
                result.append(contentsOf: lo...hi)
            } else if let v = Int(chunk), range.contains(v) {
                result.append(v)
            } else {
                return nil
            }
        }
        return .some(result.isEmpty ? nil : result)
    }

    // MARK: - Plain English

    public static func describe(_ expr: String) -> String {
        guard let c = parse(expr) else { return expr }
        var parts: [String] = []
        parts.append(describeDays(c))
        parts.append(describeTime(c))
        return parts.joined(separator: " · ")
    }

    private static func describeDays(_ c: CronExpression) -> String {
        if let wd = c.weekday {
            if wd == [1, 2, 3, 4, 5] { return "Weekdays" }
            if wd == [0, 6] || wd == [6, 0] { return "Weekends" }
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return wd.compactMap { (0..<names.count).contains($0) ? names[$0] : nil }.joined(separator: ", ")
        }
        return "Every day"
    }

    private static func describeTime(_ c: CronExpression) -> String {
        let hour = c.hour?.first ?? 0
        let minute = c.minute?.first ?? 0
        var f = DateComponents()
        f.hour = hour; f.minute = minute
        let cal = Calendar(identifier: .gregorian)
        if let date = cal.date(from: f) {
            let formatter = DateFormatter()
            formatter.dateFormat = minute == 0 ? "h a" : "h:mm a"
            return formatter.string(from: date)
        }
        return "\(hour):\(minute)"
    }

    // MARK: - launchd encoding

    /// Returns the array form `StartCalendarInterval` accepts (one entry per
    /// time-of-day for each weekday/day combination). For simple expressions
    /// (no day-of-month + weekday product), returns a single dict.
    public static func launchdCalendarIntervals(_ expr: String) -> [[String: Int]]? {
        guard let c = parse(expr) else { return nil }
        var base: [String: Int] = [:]
        if let m = c.minute, m.count == 1 { base["Minute"] = m[0] }
        if let h = c.hour, h.count == 1 { base["Hour"] = h[0] }
        // Expand weekday list into multiple entries — launchd requires this for lists.
        if let weekdays = c.weekday, !weekdays.isEmpty {
            return weekdays.map { wd in
                var d = base
                d["Weekday"] = wd
                return d
            }
        }
        // Expand day-of-month list.
        if let days = c.day, !days.isEmpty {
            return days.map { day in
                var d = base
                d["Day"] = day
                return d
            }
        }
        return [base]
    }
}
