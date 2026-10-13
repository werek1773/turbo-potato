import Foundation
import Testing
@testable import BoulderKit

@Suite("Session recap")
struct SessionRecapTests {
    let gym = UUID()
    let grades: [Grade]
    let byId: [UUID: Grade]
    let today = LocalDate("2026-10-08")!

    init() {
        let gymId = gym
        grades = (1...9).map { Grade(id: UUID(), gymId: gymId, label: "\($0)", sortOrder: $0) }
        byId = Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0) })
    }

    func ascent(_ problem: UUID, _ day: String, _ result: AscentResult, _ g: Int) -> Ascent {
        Ascent(gymId: gym, problemId: problem, localDate: LocalDate(day)!, result: result,
               gradeIdSnapshot: grades[g - 1].id)
    }

    func ascent(_ day: String, _ result: AscentResult, _ g: Int) -> Ascent {
        ascent(UUID(), day, result, g)
    }

    @Test func firstSessionIsCelebratedWithoutComparisons() {
        let day = [ascent("2026-10-08", .top, 3), ascent("2026-10-08", .flash, 2)]
        let recap = SessionRecap.make(day: today, dayAscents: day, history: day, grades: byId, today: today)
        #expect(recap.highlights == [.firstSession])
        #expect(recap.sessionNumber == 1)
        #expect(recap.previous == nil && recap.averageSends == nil)
        #expect(recap.sends == 2)
        #expect(recap.recent.map(\.date) == [today])
    }

    @Test func recordsNewSendsAndAverage() {
        let repeated = UUID()
        let history = [
            ascent(repeated, "2026-09-24", .top, 4),
            ascent("2026-09-24", .flash, 3),
            ascent("2026-10-01", .top, 5),
            ascent("2026-10-01", .project, 6),
            // A stale copy of today's log in the history is ignored.
            ascent("2026-10-08", .project, 1),
        ]
        let day = [
            ascent(repeated, "2026-10-08", .top, 4),
            ascent("2026-10-08", .top, 6),
            ascent("2026-10-08", .flash, 4),
            ascent("2026-10-08", .top, 3),
        ]
        let recap = SessionRecap.make(day: today, dayAscents: day, history: history, grades: byId, today: today)
        #expect(recap.sessionNumber == 3)
        #expect(recap.summary.hardestTop?.label == "6")
        #expect(recap.previousBest?.label == "5")
        #expect(recap.previous?.date == LocalDate("2026-10-01")!)
        #expect(recap.previous?.sends == 1)
        #expect(recap.averageSends == 1.5)
        #expect(recap.newSends == 3)
        #expect(recap.isRecord)
        #expect(recap.weekStreak == 3)
        #expect(recap.highlights == [
            .gradeRecord(grades[5], previous: grades[4]),
            .flashRecord(grades[3], previous: grades[2]),
            .newSends(3),
            .aboveAverage(3),
            .weekStreak(3),
        ])
        #expect(recap.recent.map(\.sends) == [2, 1, 4])
    }

    @Test func noRecordWhenMatchingTheBest() {
        let history = [ascent("2026-10-01", .top, 5), ascent("2026-10-01", .top, 5), ascent("2026-10-01", .top, 5)]
        let day = [ascent("2026-10-08", .top, 5)]
        let recap = SessionRecap.make(day: today, dayAscents: day, history: history, grades: byId, today: today)
        #expect(!recap.isRecord)
        #expect(recap.highlights == [.newSends(1), .weekStreak(2)])
    }

    @Test func pastDayComparesOnlyWithEarlierDays() {
        let history = [
            ascent("2026-09-01", .top, 3),
            ascent("2026-09-20", .top, 7),  // later than the edited day
        ]
        let day = [ascent("2026-09-10", .top, 5)]
        let recap = SessionRecap.make(day: LocalDate("2026-09-10")!, dayAscents: day, history: history,
                                      grades: byId, today: today)
        #expect(recap.sessionNumber == 2)
        #expect(recap.previousBest?.label == "3")
        #expect(recap.isRecord)
        #expect(recap.recent.map(\.date.description) == ["2026-09-01", "2026-09-10"])
        // The streak is about this week, so it is not a highlight of an old day.
        #expect(!recap.highlights.contains { if case .weekStreak = $0 { true } else { false } })
    }

    @Test func talliesPerDay() {
        let tallies = SessionRecap.tallies([
            ascent("2026-10-01", .flash, 3), ascent("2026-10-01", .project, 3), ascent("2026-09-01", .top, 2),
        ])
        #expect(tallies.map(\.date.description) == ["2026-09-01", "2026-10-01"])
        #expect(tallies[1].flashes == 1 && tallies[1].projects == 1 && tallies[1].sends == 1)
    }
}
