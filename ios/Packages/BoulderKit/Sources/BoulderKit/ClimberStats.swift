import Foundation

// Statistics of one climber in one gym ("Postępy"). Everything here is
// computed from the private journal on the device.

/// Lifetime totals: distinct problems, best result per problem.
public struct ClimberOverview: Hashable, Sendable {
    /// Distinct problems topped (flashes included).
    public let sends: Int
    public let flashes: Int
    /// Days with a session or a logged ascent.
    public let climbingDays: Int
    public let hardestTop: Grade?
    public let hardestFlash: Grade?
}

/// Share of limiter tags on unfinished projects in a recent window.
public struct WeaknessProfile: Hashable, Sendable {
    public let since: LocalDate
    /// Project entries in the window (tagged or not).
    public let projects: Int
    /// Project entries with at least one limiter tag.
    public let taggedProjects: Int
    public let shares: [LimiterShare]

    public var isEmpty: Bool { shares.isEmpty }
}

/// One day of the session calendar.
public struct CalendarDay: Hashable, Sendable, Identifiable {
    public let date: LocalDate
    /// A session or an ascent on that day.
    public let climbed: Bool
    /// Entries logged that day (tops, flashes and projects).
    public let ascents: Int
    public let isFuture: Bool

    public var id: LocalDate { date }
}

/// A Monday-to-Sunday row of the session calendar.
public struct CalendarWeek: Hashable, Sendable, Identifiable {
    public let start: LocalDate
    public let days: [CalendarDay]

    public var id: LocalDate { start }
    public var climbed: Bool { days.contains(where: \.climbed) }
}

extension PersonalStats {
    /// Days with a session row or at least one logged ascent.
    public static func climbingDays(sessionDates: [LocalDate], ascents: [Ascent]) -> Set<LocalDate> {
        Set(sessionDates).union(ascents.map(\.localDate))
    }

    public static func overview(
        ascents: [Ascent], sessionDates: [LocalDate], grades: [UUID: Grade]
    ) -> ClimberOverview {
        let best = bestResults(ascents).values.filter(\.result.isTop)
        func hardest(_ ascents: some Sequence<Ascent>) -> Grade? {
            ascents.compactMap { grades[$0.gradeIdSnapshot] }.max { $0.sortOrder < $1.sortOrder }
        }
        let flashes = best.filter { $0.result == .flash }
        return ClimberOverview(
            sends: best.count,
            flashes: flashes.count,
            climbingDays: climbingDays(sessionDates: sessionDates, ascents: ascents).count,
            hardestTop: hardest(best),
            hardestFlash: hardest(flashes)
        )
    }

    /// The grade pyramid as a ladder, hardest first: every grade of the
    /// scale from the easiest up to the hardest topped one, with zero rows
    /// for the gaps, so a missing step is visible. Grades no longer in use
    /// appear only when something was topped on them.
    public static func pyramidLadder(ascents: [Ascent], grades: [Grade]) -> [PyramidLevel] {
        let levels = pyramid(ascents: ascents, grades: grades)
        guard let top = levels.first?.grade.sortOrder else { return [] }
        let byGrade = Dictionary(uniqueKeysWithValues: levels.map { ($0.grade.id, $0) })
        return grades
            .filter { $0.sortOrder <= top && ($0.isActive || byGrade[$0.id] != nil) }
            .sorted { $0.sortOrder > $1.sortOrder }
            .map { byGrade[$0.id] ?? PyramidLevel(grade: $0, flashes: 0, tops: 0) }
    }

    /// Limiter shares on projects of the last `weeks` weeks (including today).
    public static func weaknessProfile(ascents: [Ascent], today: LocalDate, weeks: Int = 6) -> WeaknessProfile {
        let since = today.adding(days: -(weeks * 7 - 1))
        let projects = ascents.filter { $0.result == .project && $0.localDate >= since && $0.localDate <= today }
        return WeaknessProfile(
            since: since,
            projects: projects.count,
            taggedProjects: projects.filter { !$0.limiters.isEmpty }.count,
            shares: weaknesses(ascents: projects, since: since)
        )
    }

    /// The longest run of consecutive ISO weeks with at least one session.
    public static func longestWeekStreak(sessionDates: [LocalDate]) -> Int {
        let weeks = Set(sessionDates.map(SessionCalendar.weekStart)).sorted()
        var longest = 0, current = 0
        var previous: LocalDate?
        for week in weeks {
            current = previous.map { $0.adding(days: 7) == week } == true ? current + 1 : 1
            longest = max(longest, current)
            previous = week
        }
        return longest
    }
}

public enum SessionCalendar {
    /// 0 = Monday … 6 = Sunday.
    public static func weekday(of date: LocalDate) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day))!
        // Gregorian weekday: 1 = Sunday … 7 = Saturday.
        return (calendar.component(.weekday, from: day) + 5) % 7
    }

    /// Monday of the ISO week containing `date`.
    public static func weekStart(_ date: LocalDate) -> LocalDate {
        date.adding(days: -weekday(of: date))
    }

    /// The last `count` weeks, oldest first, ending with the week of `today`.
    public static func weeks(
        sessionDates: [LocalDate], ascents: [Ascent], today: LocalDate, count: Int
    ) -> [CalendarWeek] {
        guard count > 0 else { return [] }
        let climbed = PersonalStats.climbingDays(sessionDates: sessionDates, ascents: ascents)
        let perDay = Dictionary(grouping: ascents, by: \.localDate).mapValues(\.count)
        let firstMonday = weekStart(today).adding(days: -7 * (count - 1))
        return (0..<count).map { week in
            let start = firstMonday.adding(days: 7 * week)
            let days = (0..<7).map { offset -> CalendarDay in
                let date = start.adding(days: offset)
                return CalendarDay(date: date, climbed: climbed.contains(date),
                                   ascents: perDay[date] ?? 0, isFuture: date > today)
            }
            return CalendarWeek(start: start, days: days)
        }
    }
}

/// Polish plural forms: 1 top, 2 topy, 5 topów, 22 topy, 12 topów.
public enum PolishPlural: Sendable {
    case one, few, many

    public init(_ count: Int) {
        let n = abs(count)
        let lastTwo = n % 100, last = n % 10
        if n == 1 {
            self = .one
        } else if (2...4).contains(last) && !(12...14).contains(lastTwo) {
            self = .few
        } else {
            self = .many
        }
    }

    /// "\(count) \(form)".
    public static func format(_ count: Int, one: String, few: String, many: String) -> String {
        let form = switch PolishPlural(count) {
        case .one: one
        case .few: few
        case .many: many
        }
        return "\(count) \(form)"
    }
}
