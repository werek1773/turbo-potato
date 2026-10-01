import Foundation

public struct PyramidLevel: Hashable, Sendable, Identifiable {
    public let grade: Grade
    public let flashes: Int
    public let tops: Int

    public var id: UUID { grade.id }
    public var total: Int { flashes + tops }
}

public struct LimiterShare: Hashable, Sendable, Identifiable {
    public let limiter: Limiter
    public let count: Int
    public let share: Double

    public var id: Limiter { limiter }
}

public enum PersonalStats {
    /// Best result per problem: a flash counts once as a flash, repeats do not count.
    public static func bestResults(_ ascents: [Ascent]) -> [UUID: Ascent] {
        var best: [UUID: Ascent] = [:]
        for ascent in ascents {
            if let current = best[ascent.problemId], current.result.rank >= ascent.result.rank { continue }
            best[ascent.problemId] = ascent
        }
        return best
    }

    public static func toppedProblemIds(_ ascents: [Ascent]) -> Set<UUID> {
        Set(ascents.filter { $0.result.isTop }.map(\.problemId))
    }

    /// Grade pyramid of distinct problems topped, hardest grade first.
    public static func pyramid(ascents: [Ascent], grades: [Grade]) -> [PyramidLevel] {
        let best = bestResults(ascents).values.filter { $0.result.isTop }
        let byGrade = Dictionary(grouping: best, by: \.gradeIdSnapshot)
        return grades
            .sorted { $0.sortOrder > $1.sortOrder }
            .compactMap { grade in
                guard let topped = byGrade[grade.id], !topped.isEmpty else { return nil }
                let flashes = topped.filter { $0.result == .flash }.count
                return PyramidLevel(grade: grade, flashes: flashes, tops: topped.count - flashes)
            }
    }

    /// What most often stops unfinished projects since `since`.
    public static func weaknesses(ascents: [Ascent], since: LocalDate) -> [LimiterShare] {
        let limiters = ascents
            .filter { $0.result == .project && $0.localDate >= since }
            .flatMap(\.limiters)
        guard !limiters.isEmpty else { return [] }
        let counts = Dictionary(grouping: limiters, by: { $0 }).mapValues(\.count)
        let total = Double(limiters.count)
        return counts
            .map { LimiterShare(limiter: $0.key, count: $0.value, share: Double($0.value) / total) }
            .sorted { ($0.count, $1.limiter.rawValue) > ($1.count, $0.limiter.rawValue) }
    }

    /// Consecutive ISO weeks with at least one session, ending with the
    /// current or the previous week.
    public static func weekStreak(sessionDates: [LocalDate], today: LocalDate) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func weekStart(_ date: LocalDate) -> Date {
            let day = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day))!
            return calendar.dateInterval(of: .weekOfYear, for: day)!.start
        }
        let weeks = Set(sessionDates.map(weekStart))
        var cursor = weekStart(today)
        if !weeks.contains(cursor) {
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor)!
        }
        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor)!
        }
        return streak
    }
}

/// Summary of one climbing day, shown on top of "Podsumuj sesję".
public struct DaySummary: Hashable, Sendable {
    public let tops: Int
    public let flashes: Int
    public let projects: Int
    /// Hardest grade topped that day (by sort order).
    public let hardestTop: Grade?

    public var logged: Int { tops + flashes + projects }

    public static func of(_ ascents: [Ascent], grades: [UUID: Grade]) -> DaySummary {
        let topped = ascents.filter(\.result.isTop)
        let hardest = topped
            .compactMap { grades[$0.gradeIdSnapshot] }
            .max { $0.sortOrder < $1.sortOrder }
        return DaySummary(
            tops: ascents.filter { $0.result == .top }.count,
            flashes: ascents.filter { $0.result == .flash }.count,
            projects: ascents.filter { $0.result == .project }.count,
            hardestTop: hardest
        )
    }

    /// Problems tried before `day` cannot be flashed on `day`.
    public static func flashableProblemIds(
        problemIds: [UUID], history: [Ascent], day: LocalDate
    ) -> Set<UUID> {
        let triedBefore = Set(history.filter { $0.localDate < day }.map(\.problemId))
        return Set(problemIds.filter { !triedBefore.contains($0) })
    }
}
