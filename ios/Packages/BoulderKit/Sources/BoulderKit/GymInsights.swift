import Foundation

// Gym statistics for managers and routesetters, read from the anonymous
// daily snapshot (`problem_stats`). Every number in the snapshot already
// counts at least 5 climbers and is rounded down to a multiple of 5; nil
// means "hidden". Nothing here un-hides a cell: sums only add published
// numbers, and a hidden count is treated as zero.

public struct LimiterCount: Hashable, Sendable, Identifiable {
    public let limiter: Limiter
    /// Climbers who reported it (published, rounded).
    public let climbers: Int

    public var id: Limiter { limiter }
}

/// One active problem with its snapshot row.
public struct ProblemInsight: Hashable, Sendable, Identifiable {
    public let problem: ActiveProblem
    public let grade: Grade?
    public let stats: ProblemStats

    public var id: UUID { problem.id }

    /// Climbers who logged it (rounded down to 5); nil when hidden.
    public var climbers: Int? { stats.climbers }

    /// Tops (flashes included) per climber; nil when either count is hidden.
    public var sendRate: Double? {
        guard let climbers = stats.climbers, climbers > 0, let tops = stats.tops else { return nil }
        return min(1, Double(tops) / Double(climbers))
    }

    public var flashRate: Double? {
        guard let climbers = stats.climbers, climbers > 0, let flashes = stats.flashes else { return nil }
        return min(1, Double(flashes) / Double(climbers))
    }

    public var communityGrade: PerceivedGrade? { stats.communityGrade }

    /// Published limiters, most reported first.
    public var limiters: [LimiterCount] {
        stats.limiters
            .compactMap { key, value in Limiter(rawValue: key).map { LimiterCount(limiter: $0, climbers: value) } }
            .filter { $0.climbers > 0 }
            .sorted { ($0.climbers, $1.limiter.rawValue) > ($1.climbers, $0.limiter.rawValue) }
    }
}

/// Aggregates of one grade over its active problems with data.
public struct GradeInsight: Hashable, Sendable, Identifiable {
    public let grade: Grade
    /// Active problems of this grade.
    public let activeProblems: Int
    /// Of those, problems with a published snapshot.
    public let problemsWithData: Int
    public let climbers: Int
    /// Published tops (hidden counted as zero, so the rate errs low).
    public let tops: Int
    /// Problems whose top count is published (not hidden).
    public let problemsWithTops: Int
    /// Problems the community calls soft / ok / hard.
    public let soft: Int
    public let ok: Int
    public let hard: Int

    public var id: UUID { grade.id }

    /// Nil when no top count of this grade is published: "0%" would
    /// only mean "fewer than 5 per problem".
    public var sendRate: Double? {
        climbers > 0 && problemsWithTops > 0 ? min(1, Double(tops) / Double(climbers)) : nil
    }

    public var verdicts: Int { soft + ok + hard }
}

public struct GymInsights: Hashable, Sendable {
    /// Active problems with a snapshot row.
    public let problems: [ProblemInsight]
    public let activeProblems: Int
    /// Easiest grade first; only grades with active problems.
    public let byGrade: [GradeInsight]
    /// Gym-wide limiter reports over active problems, most reported first.
    public let limiterTotals: [LimiterCount]
    public let computedAt: Date?

    public var isEmpty: Bool { problems.isEmpty }

    /// Most climbed first.
    public var popular: [ProblemInsight] {
        problems
            .filter { ($0.climbers ?? 0) > 0 }
            .sorted { lhs, rhs in
                if lhs.climbers != rhs.climbers { return (lhs.climbers ?? 0) > (rhs.climbers ?? 0) }
                return Self.byGradeThenId(lhs, rhs)
            }
    }

    /// Problems the community feels are off their grade.
    public func perceived(_ verdict: PerceivedGrade) -> [ProblemInsight] {
        problems
            .filter { $0.communityGrade == verdict }
            .sorted(by: Self.byGradeThenId)
    }

    /// Problems with published limiters, the most reported limiter first.
    public var limiterHeavy: [ProblemInsight] {
        problems
            .filter { !$0.limiters.isEmpty }
            .sorted { lhs, rhs in
                let l = lhs.limiters[0].climbers, r = rhs.limiters[0].climbers
                if l != r { return l > r }
                return Self.byGradeThenId(lhs, rhs)
            }
    }

    private static func byGradeThenId(_ lhs: ProblemInsight, _ rhs: ProblemInsight) -> Bool {
        let l = lhs.grade?.sortOrder ?? .max, r = rhs.grade?.sortOrder ?? .max
        if l != r { return l < r }
        return lhs.problem.id.uuidString < rhs.problem.id.uuidString
    }

    /// Joins the snapshot with the problems currently on the wall. Rows of
    /// removed problems are left out.
    public static func make(stats: [ProblemStats], problems: [ActiveProblem], grades: [Grade]) -> GymInsights {
        let gradesById = Dictionary(grades.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let statsById = Dictionary(stats.map { ($0.problemId, $0) }, uniquingKeysWith: { first, _ in first })
        let insights = problems.compactMap { problem in
            statsById[problem.id].map { ProblemInsight(problem: problem, grade: gradesById[problem.gradeId], stats: $0) }
        }

        let activeByGrade = Dictionary(grouping: problems, by: \.gradeId)
        let insightsByGrade = Dictionary(grouping: insights, by: \.problem.gradeId)
        let byGrade = grades
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { grade -> GradeInsight? in
                guard let active = activeByGrade[grade.id], !active.isEmpty else { return nil }
                let rows = insightsByGrade[grade.id] ?? []
                return GradeInsight(
                    grade: grade,
                    activeProblems: active.count,
                    problemsWithData: rows.count,
                    climbers: rows.compactMap(\.stats.climbers).reduce(0, +),
                    tops: rows.filter { $0.stats.climbers != nil }.compactMap(\.stats.tops).reduce(0, +),
                    problemsWithTops: rows.filter { $0.stats.climbers != nil && $0.stats.tops != nil }.count,
                    soft: rows.filter { $0.communityGrade == .soft }.count,
                    ok: rows.filter { $0.communityGrade == .ok }.count,
                    hard: rows.filter { $0.communityGrade == .hard }.count
                )
            }

        var totals: [Limiter: Int] = [:]
        for insight in insights {
            for entry in insight.limiters { totals[entry.limiter, default: 0] += entry.climbers }
        }
        let limiterTotals = totals
            .map { LimiterCount(limiter: $0.key, climbers: $0.value) }
            .sorted { ($0.climbers, $1.limiter.rawValue) > ($1.climbers, $0.limiter.rawValue) }

        return GymInsights(
            problems: insights,
            activeProblems: problems.count,
            byGrade: byGrade,
            limiterTotals: limiterTotals,
            computedAt: stats.compactMap(\.computedAt).max()
        )
    }
}
