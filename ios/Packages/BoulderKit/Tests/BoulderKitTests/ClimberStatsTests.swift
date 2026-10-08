import Foundation
import Testing
@testable import BoulderKit

@Suite("Climber statistics")
struct ClimberStatsTests {
    let gym = UUID()
    let grades: [Grade]

    init() {
        let gymId = gym
        grades = (1...9).map { Grade(id: UUID(), gymId: gymId, label: "\($0)", sortOrder: $0) }
    }

    func grade(_ n: Int) -> Grade { grades[n - 1] }

    func ascent(_ problem: UUID, _ day: String, _ result: AscentResult, _ g: Int,
                limiters: [Limiter] = []) -> Ascent {
        Ascent(gymId: gym, problemId: problem, localDate: LocalDate(day)!, result: result,
               limiters: limiters, gradeIdSnapshot: grade(g).id)
    }

    func ascent(_ day: String, _ result: AscentResult, _ g: Int, limiters: [Limiter] = []) -> Ascent {
        ascent(UUID(), day, result, g, limiters: limiters)
    }

    @Test func ladderFillsGapsUpToTheHardestTop() {
        let ascents = [
            ascent("2026-09-01", .flash, 2),
            ascent("2026-09-01", .top, 2),
            ascent("2026-09-02", .top, 5),
            ascent("2026-09-02", .project, 7),
        ]
        let ladder = PersonalStats.pyramidLadder(ascents: ascents, grades: grades.shuffled())
        #expect(ladder.map(\.grade.label) == ["5", "4", "3", "2", "1"])
        #expect(ladder[0].tops == 1)
        #expect(ladder[1].total == 0 && ladder[2].total == 0)
        #expect(ladder[3].flashes == 1 && ladder[3].tops == 1)
        #expect(PersonalStats.pyramidLadder(ascents: [], grades: grades).isEmpty)
    }

    @Test func ladderSkipsRetiredGradesWithoutTops() {
        var retired = grade(3)
        retired.isActive = false
        let scale = grades.map { $0.id == retired.id ? retired : $0 }
        let ladder = PersonalStats.pyramidLadder(ascents: [ascent("2026-09-01", .top, 4)], grades: scale)
        #expect(ladder.map(\.grade.label) == ["4", "2", "1"])
    }

    @Test func overviewCountsDistinctProblems() {
        let p = UUID()
        let ascents = [
            ascent(p, "2026-09-01", .project, 6),
            ascent(p, "2026-09-03", .top, 6),
            ascent(p, "2026-09-05", .top, 6),
            ascent("2026-09-05", .flash, 4),
        ]
        let byId = Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0) })
        let overview = PersonalStats.overview(
            ascents: ascents, sessionDates: [LocalDate("2026-09-10")!], grades: byId)
        #expect(overview.sends == 2)
        #expect(overview.flashes == 1)
        #expect(overview.climbingDays == 4)
        #expect(overview.hardestTop?.label == "6")
        #expect(overview.hardestFlash?.label == "4")
    }

    @Test func weaknessProfileLooksSixWeeksBack() {
        let today = LocalDate("2026-10-08")!
        let ascents = [
            ascent("2026-10-08", .project, 6, limiters: [.power]),
            ascent("2026-08-28", .project, 6, limiters: [.power, .beta]),   // day 42: in
            ascent("2026-08-27", .project, 6, limiters: [.fear]),           // day 43: out
            ascent("2026-09-15", .project, 6),                              // untagged
            ascent("2026-09-15", .top, 6, limiters: [.core]),               // not a project
        ]
        let profile = PersonalStats.weaknessProfile(ascents: ascents, today: today)
        #expect(profile.since == LocalDate("2026-08-28")!)
        #expect(profile.projects == 3)
        #expect(profile.taggedProjects == 2)
        #expect(profile.shares.map(\.limiter) == [.power, .beta])
        #expect(abs(profile.shares[0].share - 2.0 / 3.0) < 0.0001)
    }

    @Test func calendarWeeksStartOnMonday() {
        let today = LocalDate("2026-10-08")!  // Thursday
        #expect(SessionCalendar.weekday(of: today) == 3)
        #expect(SessionCalendar.weekStart(today) == LocalDate("2026-10-05")!)
        #expect(SessionCalendar.weekStart(LocalDate("2026-10-04")!) == LocalDate("2026-09-28")!)

        let ascents = [ascent("2026-10-06", .top, 3), ascent("2026-10-06", .flash, 2)]
        let weeks = SessionCalendar.weeks(
            sessionDates: [LocalDate("2026-09-30")!], ascents: ascents, today: today, count: 3)
        #expect(weeks.map(\.start) == ["2026-09-21", "2026-09-28", "2026-10-05"].map { LocalDate($0)! })
        #expect(weeks.allSatisfy { $0.days.count == 7 })
        #expect(weeks[0].climbed == false)
        #expect(weeks[1].days[2].climbed && weeks[1].days[2].ascents == 0)
        #expect(weeks[2].days[1].ascents == 2)
        #expect(weeks[2].days[4].isFuture && !weeks[2].days[3].isFuture)
    }

    @Test func longestWeekStreak() {
        let dates = ["2026-08-03", "2026-08-12", "2026-08-19", "2026-08-20", "2026-09-07", "2026-09-14"]
            .map { LocalDate($0)! }
        #expect(PersonalStats.longestWeekStreak(sessionDates: dates) == 3)
        #expect(PersonalStats.longestWeekStreak(sessionDates: []) == 0)
        // Across the new year (ISO week 53 → week 1).
        let newYear = ["2026-12-28", "2027-01-04"].map { LocalDate($0)! }
        #expect(PersonalStats.longestWeekStreak(sessionDates: newYear) == 2)
    }

    @Test func polishPlural() {
        func tops(_ n: Int) -> String { PolishPlural.format(n, one: "top", few: "topy", many: "topów") }
        #expect(tops(0) == "0 topów")
        #expect(tops(1) == "1 top")
        #expect(tops(3) == "3 topy")
        #expect(tops(5) == "5 topów")
        #expect(tops(12) == "12 topów")
        #expect(tops(22) == "22 topy")
        #expect(tops(111) == "111 topów")
    }
}
