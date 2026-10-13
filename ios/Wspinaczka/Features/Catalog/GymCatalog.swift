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
    /// My ascents at this gym, with writes still in the outbox applied.
    private(set) var myAscents: [Ascent] = []
    private(set) var isLoading = false
    /// When the data on screen comes from the device's cache (offline or
    /// not refreshed yet): the time it was downloaded.
    private(set) var cachedAt: Date?
    /// My ascents as last confirmed by the server — what the cache stores.
    @ObservationIgnored private var serverAscents: [Ascent] = []

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
        restoreFromCacheIfEmpty()

        let sentBefore = JournalOutbox.shared.sentSequence
        async let grades = backend.grades(gymId: gym.id)
        async let sectors = backend.sectors(gymId: gym.id)
        async let problems = backend.activeProblems(gymId: gym.id)
        async let ascents = backend.myAscents(gymId: gym.id)

        let loadedSectors = try await sectors
        let photoIds = loadedSectors.compactMap(\.currentPhotoId)
        let loadedPhotos = try await backend.currentPhotos(gymId: gym.id, photoIds: photoIds)

        self.grades = try await grades
        self.sectors = loadedSectors
        self.photos = Dictionary(uniqueKeysWithValues: loadedPhotos.map { ($0.id, $0) })
        self.problems = try await problems
        setServerAscents(try await ascents, sentBefore: sentBefore)
        cachedAt = nil
        saveToCache()
    }

    // MARK: My ascents & cache

    /// Re-downloads only my ascents, e.g. once the outbox has been sent.
    func refreshMyAscents() async throws {
        let sentBefore = JournalOutbox.shared.sentSequence
        setServerAscents(try await backend.myAscents(gymId: gym.id), sentBefore: sentBefore)
        saveToCache()
    }

    /// Shows a journal write at once, before it reaches the server.
    func applyLocal(_ write: PendingAscent) {
        myAscents = Outbox.merge(server: myAscents, pending: [write])
    }

    /// `sentBefore`: the outbox's `sentSequence` when the download started;
    /// writes sent since then may be missing from `ascents`.
    private func setServerAscents(_ ascents: [Ascent], sentBefore: Int? = nil) {
        let outbox = JournalOutbox.shared
        let sentMeanwhile = sentBefore.map { outbox.ascentsSent(after: $0, gymId: gym.id) } ?? []
        serverAscents = Outbox.merge(server: ascents, pending: sentMeanwhile)
        myAscents = Outbox.merge(server: serverAscents, pending: outbox.pendingAscents(gymId: gym.id))
    }

    private func restoreFromCacheIfEmpty() {
        guard grades.isEmpty, sectors.isEmpty, let userId = backend.client.auth.currentUser?.id,
              let snapshot = LocalStore.catalog(userId: userId, gymId: gym.id) else { return }
        grades = snapshot.grades
        sectors = snapshot.sectors
        photos = Dictionary(snapshot.photos.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        problems = snapshot.problems
        setServerAscents(snapshot.myAscents)
        cachedAt = snapshot.savedAt
    }

    private func saveToCache() {
        guard let userId = backend.client.auth.currentUser?.id else { return }
        let snapshot = CatalogSnapshot(
            gymId: gym.id, grades: grades, sectors: sectors, photos: Array(photos.values),
            problems: problems, myAscents: serverAscents
        )
        Task.detached(priority: .utility) {
            LocalStore.saveCatalog(snapshot, userId: userId)
        }
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
