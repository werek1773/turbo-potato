import Foundation
import Testing
@testable import BoulderKit

@Suite("Gym insights")
struct GymInsightsTests {
    let gym = UUID()
    let sector = UUID()
    let photo = UUID()
    let four: Grade
    let five: Grade
    let six: Grade

    init() {
        four = Grade(id: UUID(), gymId: gym, label: "4", sortOrder: 4)
        five = Grade(id: UUID(), gymId: gym, label: "5", sortOrder: 5)
        six = Grade(id: UUID(), gymId: gym, label: "6", sortOrder: 6)
    }

    func problem(_ grade: Grade) -> ActiveProblem {
        ActiveProblem(id: UUID(), gymId: gym, sectorId: sector, gradeId: grade.id, holdColor: .red,
                      setAt: .now, photoId: photo, pinX: 0.5, pinY: 0.5)
    }

    @Test func joinsSnapshotWithTheWall() {
        let a = problem(four), b = problem(four), c = problem(five), d = problem(six)
        let removed = UUID()
        let stats = [
            ProblemStats(problemId: a.id, climbers: 20, tops: 15, flashes: 5, perceivedSoft: 10,
                         limiters: ["power": 10]),
            ProblemStats(problemId: b.id, climbers: 25, tops: nil, perceivedHard: 5,
                         limiters: ["finger_strength": 20, "power": 5, "unknown_tag": 5]),
            ProblemStats(problemId: c.id, climbers: 30, tops: 10, perceivedOk: 5, perceivedHard: 5),
            ProblemStats(problemId: removed, climbers: 50, tops: 50),
        ]
        let insights = GymInsights.make(stats: stats, problems: [a, b, c, d], grades: [six, five, four])

        #expect(insights.problems.count == 3)
        #expect(insights.activeProblems == 4)
        #expect(insights.popular.map(\.id) == [c.id, b.id, a.id])

        #expect(insights.byGrade.map(\.grade.label) == ["4", "5", "6"])
        let fours = insights.byGrade[0]
        #expect(fours.activeProblems == 2 && fours.problemsWithData == 2)
        #expect(fours.climbers == 45 && fours.tops == 15)
        #expect(abs((fours.sendRate ?? 0) - 1.0 / 3.0) < 0.0001)
        #expect(fours.soft == 1 && fours.hard == 1 && fours.ok == 0)
        // A tie between ok and hard is no verdict.
        #expect(insights.byGrade[1].verdicts == 0)
        #expect(insights.byGrade[2].problemsWithData == 0 && insights.byGrade[2].sendRate == nil)

        let rowA = insights.problems.first { $0.id == a.id }!
        #expect(rowA.sendRate == 0.75 && rowA.flashRate == 0.25)
        let rowB = insights.problems.first { $0.id == b.id }!
        #expect(rowB.sendRate == nil)
        #expect(rowB.limiters.map(\.limiter) == [.fingerStrength, .power])

        #expect(insights.perceived(.soft).map(\.id) == [a.id])
        #expect(insights.perceived(.hard).map(\.id) == [b.id])
        #expect(insights.limiterHeavy.map(\.id) == [b.id, a.id])
        #expect(insights.limiterTotals.map(\.limiter) == [.fingerStrength, .power])
        #expect(insights.limiterTotals[0].climbers == 20)
    }

    @Test func hiddenTopsGiveNoRate() {
        let a = problem(four)
        let stats = [ProblemStats(problemId: a.id, climbers: 10, tops: nil)]
        let insights = GymInsights.make(stats: stats, problems: [a], grades: [four])
        #expect(insights.byGrade[0].climbers == 10)
        #expect(insights.byGrade[0].sendRate == nil)
    }

    @Test func emptySnapshot() {
        let insights = GymInsights.make(stats: [], problems: [problem(four)], grades: [four])
        #expect(insights.isEmpty)
        #expect(insights.byGrade.first?.problemsWithData == 0)
        #expect(insights.computedAt == nil)
    }

    @Test func decodesTheSnapshotTimestamp() throws {
        let json = #"{"problem_id":"7c9e6679-7425-40de-944b-e07fc1f90ae7","computed_at":"2026-10-07T02:17:00Z","climbers":5,"tops":5,"flashes":null,"perceived_soft":null,"perceived_ok":null,"perceived_hard":null,"limiters":{}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stats = try decoder.decode(ProblemStats.self, from: Data(json.utf8))
        #expect(stats.computedAt != nil)
        #expect(stats.climbers == 5)
    }
}
