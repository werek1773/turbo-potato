import BoulderKit
import Foundation
import Observation

/// Everything the catalog of one gym shows, loaded in one go.
@MainActor
@Observable
final class GymCatalog {
    let gym: Gym
    let backend: Backend

    private(set) var grades: [Grade] = []
    private(set) var sectors: [Sector] = []
    private(set) var photos: [UUID: SectorPhoto] = [:]
    private(set) var problems: [ActiveProblem] = []
    /// Route holds of active problems, by problem id.
    private(set) var routes: [UUID: [RouteHold]] = [:]
    private(set) var myAscents: [Ascent] = []
    private(set) var isLoading = false

    var filter = ProblemFilter()

    init(gym: Gym, backend: Backend) {
        self.gym = gym
        self.backend = backend
    }

    var gradesById: [UUID: Grade] {
        Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0) })
    }

    var toppedProblemIds: Set<UUID> { PersonalStats.toppedProblemIds(myAscents) }

    var lastVisit: LocalDate? { myAscents.map(\.localDate).max() }

    var coverage: [GradeCoverage] {
        Coverage.byGrade(problems: problems, grades: grades, toppedProblemIds: toppedProblemIds)
    }

    var visibleProblemIds: Set<UUID> {
        Set(filter.apply(to: problems, grades: gradesById, toppedProblemIds: toppedProblemIds,
                         timeZone: gym.timeZone).map(\.id))
    }

    func problems(in sector: Sector) -> [ActiveProblem] {
        problems.filter { $0.sectorId == sector.id }
    }

    func load() async throws {
        isLoading = true
        defer { isLoading = false }

        async let grades = backend.grades(gymId: gym.id)
        async let sectors = backend.sectors(gymId: gym.id)
        async let problems = backend.activeProblems(gymId: gym.id)
        async let ascents = backend.myAscents(gymId: gym.id)
        async let routeHolds = backend.currentRoutes(gymId: gym.id)

        let loadedSectors = try await sectors
        let photoIds = loadedSectors.compactMap(\.currentPhotoId)
        let loadedPhotos = try await backend.currentPhotos(gymId: gym.id, photoIds: photoIds)

        self.grades = try await grades
        self.sectors = loadedSectors
        self.photos = Dictionary(uniqueKeysWithValues: loadedPhotos.map { ($0.id, $0) })
        self.problems = try await problems
        self.myAscents = try await ascents
        // Routes are extra: a catalog without them still works.
        self.routes = Dictionary(grouping: (try? await routeHolds) ?? [], by: \.problemId)
    }

    func route(of problem: ActiveProblem) -> [RouteHold] {
        routes[problem.id] ?? []
    }

    /// New or changed since my last visit (or within the last week).
    func freshness(of problem: ActiveProblem) -> Freshness? {
        Freshness.of(problem, lastVisit: lastVisit, now: .now, timeZone: gym.timeZone)
    }

    /// The last day I topped (or flashed) the problem.
    func lastTop(of problem: ActiveProblem) -> LocalDate? {
        myAscents
            .filter { $0.problemId == problem.id && $0.result != .project }
            .map(\.localDate)
            .max()
    }

    var areas: [SectorArea] { Sector.groupedByArea(sectors) }

    var today: LocalDate { ClimbingDay.today(in: gym.timeZone) }

    var upcomingResets: [UpcomingReset] {
        Resets.upcoming(sectors: sectors, problems: problems,
                        toppedProblemIds: toppedProblemIds, today: today)
    }

    func upcomingReset(for sector: Sector) -> UpcomingReset? {
        upcomingResets.first { $0.sector.id == sector.id }
    }

    func setNextReset(for sector: Sector, on date: LocalDate?) async throws {
        try await backend.setNextReset(sectorId: sector.id, on: date)
        try await load()
    }

    /// Appends a sector at the end of the walking order.
    func addSector(named name: String, area: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArea = area.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        try await backend.addSector(
            gymId: gym.id,
            name: trimmedName,
            area: trimmedArea.isEmpty ? nil : trimmedArea,
            sortOrder: (sectors.map(\.sortOrder).max() ?? 0) + 1
        )
        try await load()
    }
}
