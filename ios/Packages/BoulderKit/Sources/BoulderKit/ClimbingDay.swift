import Foundation

/// A climbing day ends at 04:00 local gym time, so a late session belongs to
/// the day it started. Mirrors `private.climbing_date` in the database, which
/// subtracts the four hours from the local wall-clock time.
public enum ClimbingDay {
    public static let boundaryHours = 4

    public static func localDate(for instant: Date, in timeZone: TimeZone) -> LocalDate {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let wallClock = local.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let wallClockDate = utc.date(from: wallClock)!
        let shifted = wallClockDate.addingTimeInterval(-Double(boundaryHours) * 3600)
        let day = utc.dateComponents([.year, .month, .day], from: shifted)
        return LocalDate(year: day.year!, month: day.month!, day: day.day!)
    }

    public static func today(in timeZone: TimeZone, now: Date = .now) -> LocalDate {
        localDate(for: now, in: timeZone)
    }
}
