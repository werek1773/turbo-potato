import BoulderKit
import Foundation
import Observation

/// "Postępy" of one climber in one gym: the catalog (grades, problems on the
/// wall, my ascents) plus my session days.
@MainActor
@Observable
final class ClimberStatsModel {
    let catalog: GymCatalog
    private(set) var sessionDates: [LocalDate] = []
    private(set) var hasLoaded = false

    static let calendarWeeks = 10

    init(gym: Gym, backend: Backend = .shared) {
        catalog = GymCatalog(gym: gym, backend: backend)
    }

    var gym: Gym { catalog.gym }
    var ascents: [Ascent] { catalog.myAscents }
    var today: LocalDate { catalog.today }

    func load() async throws {
        let backend = catalog.backend, gymId = gym.id
        async let sessions = backend.mySessions(gymId: gymId)
        try await catalog.load()
        sessionDates = try await sessions.map(\.localDate)
        hasLoaded = true
    }

    /// Nothing logged yet: no ascents and no session days.
    var isEmpty: Bool { ascents.isEmpty && sessionDates.isEmpty }

    var overview: ClimberOverview {
        PersonalStats.overview(ascents: ascents, sessionDates: sessionDates, grades: catalog.gradesById)
    }

    var pyramid: [PyramidLevel] {
        PersonalStats.pyramidLadder(ascents: ascents, grades: catalog.grades)
    }

    var coverage: [GradeCoverage] { catalog.coverage }

    var weakness: WeaknessProfile {
        PersonalStats.weaknessProfile(ascents: ascents, today: today)
    }

    private var climbingDays: [LocalDate] {
        Array(PersonalStats.climbingDays(sessionDates: sessionDates, ascents: ascents))
    }

    var calendar: [CalendarWeek] {
        SessionCalendar.weeks(sessionDates: sessionDates, ascents: ascents, today: today,
                              count: Self.calendarWeeks)
    }

    var weekStreak: Int { PersonalStats.weekStreak(sessionDates: climbingDays, today: today) }
    var longestWeekStreak: Int { PersonalStats.longestWeekStreak(sessionDates: climbingDays) }
}
