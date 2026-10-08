import Foundation

/// Tally of one climbing day, for comparisons between sessions.
public struct DayTally: Hashable, Sendable, Identifiable {
    public let date: LocalDate
    public let flashes: Int
    public let tops: Int
    public let projects: Int

    public var id: LocalDate { date }
    /// Tops including flashes.
    public var sends: Int { flashes + tops }
}

/// The short, motivating summary after logging a day ("4 topy · 1 flash ·
/// najtrudniejszy: 6 · nowy rekord!") and how it compares with earlier days.
public struct SessionRecap: Hashable, Sendable {
    public enum Highlight: Hashable, Sendable {
        /// The very first logged day in this gym.
        case firstSession
        /// Hardest top so far (earlier days had tops, all easier).
        case gradeRecord(Grade, previous: Grade)
        /// Hardest flash so far.
        case flashRecord(Grade, previous: Grade)
        /// Problems topped for the first time (repeats excluded).
        case newSends(Int)
        /// More sends than the average of recent sessions (rounded difference).
        case aboveAverage(Int)
        /// Consecutive weeks with a session, when at least 2.
        case weekStreak(Int)
    }

    public let day: LocalDate
    public let summary: DaySummary
    /// 1-based position of this day among the logged days.
    public let sessionNumber: Int
    public let newSends: Int
    public let previousBest: Grade?
    /// The last logged day before this one.
    public let previous: DayTally?
    /// Average sends of up to `comparedSessions` earlier days.
    public let averageSends: Double?
    public let weekStreak: Int
    /// Up to `recentLimit` logged days ending with this one, oldest first.
    public let recent: [DayTally]
    public let highlights: [Highlight]

    public var sends: Int { summary.tops + summary.flashes }

    public static let comparedSessions = 5
    public static let recentLimit = 8

    /// - Parameters:
    ///   - day: the climbing day being summarized.
    ///   - dayAscents: what is logged on `day` (fresher than `history`).
    ///   - history: my ascents in this gym; entries of `day` are ignored.
    ///   - sessionDates: days with a session row (for the week streak).
    ///   - today: the current climbing day (for the week streak).
    public static func make(
        day: LocalDate,
        dayAscents: [Ascent],
        history: [Ascent],
        sessionDates: [LocalDate] = [],
        grades: [UUID: Grade],
        today: LocalDate
    ) -> SessionRecap {
        let others = history.filter { $0.localDate != day }
        let earlier = others.filter { $0.localDate < day }
        let summary = DaySummary.of(dayAscents, grades: grades)

        let earlierDays = tallies(earlier)
        let previous = earlierDays.last
        let compared = earlierDays.suffix(comparedSessions)
        let average = compared.isEmpty
            ? nil
            : Double(compared.map(\.sends).reduce(0, +)) / Double(compared.count)

        func hardest(_ ascents: [Ascent], _ results: Set<AscentResult>) -> Grade? {
            ascents.filter { results.contains($0.result) }
                .compactMap { grades[$0.gradeIdSnapshot] }
                .max { $0.sortOrder < $1.sortOrder }
        }
        let previousBest = hardest(earlier, [.top, .flash])
        let previousFlash = hardest(earlier, [.flash])
        let todayFlash = hardest(dayAscents, [.flash])

        let toppedBefore = PersonalStats.toppedProblemIds(earlier)
        let newSends = Set(dayAscents.filter(\.result.isTop).map(\.problemId))
            .subtracting(toppedBefore).count

        let thisDay = DayTally(date: day, flashes: summary.flashes, tops: summary.tops, projects: summary.projects)
        let allDays = (tallies(others) + (dayAscents.isEmpty ? [] : [thisDay])).sorted { $0.date < $1.date }
        let recent = Array(allDays.filter { $0.date <= day }.suffix(recentLimit))

        let streakDates = Array(PersonalStats.climbingDays(sessionDates: sessionDates, ascents: others + dayAscents))
        let streak = PersonalStats.weekStreak(sessionDates: streakDates, today: today)

        var highlights: [Highlight] = []
        if earlierDays.isEmpty && !dayAscents.isEmpty {
            highlights.append(.firstSession)
        }
        if let best = summary.hardestTop, let previousBest, best.sortOrder > previousBest.sortOrder {
            highlights.append(.gradeRecord(best, previous: previousBest))
        }
        if let todayFlash, let previousFlash, todayFlash.sortOrder > previousFlash.sortOrder {
            highlights.append(.flashRecord(todayFlash, previous: previousFlash))
        }
        if newSends > 0 && !earlierDays.isEmpty {
            highlights.append(.newSends(newSends))
        }
        if let average, average > 0 {
            let difference = Int((Double(thisDay.sends) - average).rounded())
            if difference >= 1 { highlights.append(.aboveAverage(difference)) }
        }
        if streak >= 2 && day == today {
            highlights.append(.weekStreak(streak))
        }

        return SessionRecap(
            day: day,
            summary: summary,
            sessionNumber: earlierDays.count + 1,
            newSends: newSends,
            previousBest: previousBest,
            previous: previous,
            averageSends: average,
            weekStreak: streak,
            recent: recent,
            highlights: highlights
        )
    }

    public var isRecord: Bool {
        highlights.contains { if case .gradeRecord = $0 { true } else { false } }
    }

    /// Per-day tallies, oldest first.
    public static func tallies(_ ascents: [Ascent]) -> [DayTally] {
        Dictionary(grouping: ascents, by: \.localDate)
            .map { date, entries in
                DayTally(
                    date: date,
                    flashes: entries.filter { $0.result == .flash }.count,
                    tops: entries.filter { $0.result == .top }.count,
                    projects: entries.filter { $0.result == .project }.count
                )
            }
            .sorted { $0.date < $1.date }
    }
}
