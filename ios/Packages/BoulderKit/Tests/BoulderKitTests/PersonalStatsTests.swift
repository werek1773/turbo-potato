import Foundation
import Testing
@testable import BoulderKit

@Suite("Personal statistics")
struct PersonalStatsTests {
    let gym = UUID()
    let four = Grade(id: UUID(), gymId: UUID(), label: "4", sortOrder: 4)
    let five = Grade(id: UUID(), gymId: UUID(), label: "5", sortOrder: 5)

    func ascent(_ problem: UUID, _ day: String, _ result: AscentResult, grade: Grade, limiters: [Limiter] = []) -> Ascent {
        Ascent(gymId: gym, problemId: problem, localDate: LocalDate(day)!, result: result,
               limiters: limiters, gradeIdSnapshot: grade.id)
    }

    @Test func pyramidCountsDistinctProblemsByBestResult() {
        let p1 = UUID(), p2 = UUID(), p3 = UUID(), p4 = UUID()
        let ascents = [
            ascent(p1, "2026-09-01", .project, grade: four),
            ascent(p1, "2026-09-05", .top, grade: four),
            ascent(p1, "2026-09-12", .top, grade: four),      // repeat, counted once
            ascent(p2, "2026-09-05", .flash, grade: four),
            ascent(p3, "2026-09-05", .top, grade: five),
            ascent(p4, "2026-09-05", .project, grade: five),  // not topped
        ]
        let pyramid = PersonalStats.pyramid(ascents: ascents, grades: [four, five])
        #expect(pyramid.map(\.grade.label) == ["5", "4"])
        #expect(pyramid[0].tops == 1 && pyramid[0].flashes == 0)
        #expect(pyramid[1].tops == 1 && pyramid[1].flashes == 1)
    }

    @Test func weaknessesComeFromRecentProjects() {
        let ascents = [
            ascent(UUID(), "2026-09-20", .project, grade: five, limiters: [.fingerStrength, .footwork]),
            ascent(UUID(), "2026-09-21", .project, grade: five, limiters: [.fingerStrength]),
            ascent(UUID(), "2026-09-21", .top, grade: five, limiters: [.endurance]),
            ascent(UUID(), "2026-06-01", .project, grade: five, limiters: [.fear]),
        ]
        let weaknesses = PersonalStats.weaknesses(ascents: ascents, since: LocalDate("2026-08-20")!)
        #expect(weaknesses.map(\.limiter) == [.fingerStrength, .footwork])
        #expect(abs(weaknesses[0].share - 2.0 / 3.0) < 0.0001)
    }

    @Test func weekStreak() {
        let today = LocalDate("2026-10-01")!  // Thursday
        let dates = ["2026-09-29", "2026-09-24", "2026-09-15", "2026-09-01"].map { LocalDate($0)! }
        #expect(PersonalStats.weekStreak(sessionDates: dates, today: today) == 3)
        // Nothing this week yet: the streak still counts up to last week.
        #expect(PersonalStats.weekStreak(sessionDates: Array(dates.dropFirst()), today: today) == 2)
        #expect(PersonalStats.weekStreak(sessionDates: [], today: today) == 0)
    }

    @Test func communityGradeNeedsAClearWinner() throws {
        let json = #"{"problem_id":"7c9e6679-7425-40de-944b-e07fc1f90ae7","climbers":10,"tops":5,"flashes":null,"perceived_soft":null,"perceived_ok":null,"perceived_hard":5,"limiters":{"finger_strength":5}}"#
        let stats = try JSONDecoder().decode(ProblemStats.self, from: Data(json.utf8))
        #expect(stats.communityGrade == .hard)
        #expect(stats.limiters["finger_strength"] == 5)
    }
}
