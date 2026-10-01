import BoulderKit
import Foundation
import Observation

/// State of "Podsumuj sesję" for one gym and one climbing day.
@MainActor
@Observable
final class SessionLog {
    let catalog: GymCatalog
    var day: LocalDate {
        didSet { if oldValue != day { Task { await reloadDay() } } }
    }

    /// My records of this day, by problem.
    private(set) var results: [UUID: Ascent] = [:]
    private(set) var session: ClimbingSession?
    private(set) var wellbeing: SessionWellbeing?
    /// Problems whose save is in flight (pins show a spinner-free dimmed state).
    private(set) var saving: Set<UUID> = []

    init(catalog: GymCatalog, day: LocalDate) {
        self.catalog = catalog
        self.day = day
    }

    var backend: Backend { catalog.backend }
    var today: LocalDate { catalog.today }

    var dayAscents: [Ascent] { Array(results.values) }

    var summary: DaySummary { DaySummary.of(dayAscents, grades: catalog.gradesById) }

    /// Problems tried on an earlier day cannot be flashed today.
    var flashable: Set<UUID> {
        DaySummary.flashableProblemIds(
            problemIds: catalog.problems.map(\.id),
            history: catalog.myAscents,
            day: day
        )
    }

    func load() async throws {
        try await catalog.load()
        try await reloadDayThrowing()
    }

    func reloadDay() async {
        try? await reloadDayThrowing()
    }

    private func reloadDayThrowing() async throws {
        let ascents = try await backend.myAscents(gymId: catalog.gym.id)
        results = Dictionary(
            ascents.filter { $0.localDate == day }.map { ($0.problemId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        session = try await backend.session(gymId: catalog.gym.id, on: day)
        if let session {
            wellbeing = try await backend.wellbeing(sessionId: session.id)
        } else {
            wellbeing = nil
        }
    }

    // MARK: Pins

    /// Tap on a pin: none → top → flash → project → none.
    func cycle(_ problem: ActiveProblem) async throws {
        let current = results[problem.id]
        let next = AscentResult.next(after: current?.result, canFlash: flashable.contains(problem.id))
        try await set(problem, result: next, keepingDetailsOf: current)
    }

    func set(
        _ problem: ActiveProblem,
        result: AscentResult?,
        attempts: AttemptsBucket? = nil,
        perceivedGrade: PerceivedGrade? = nil,
        limiters: [Limiter] = [],
        note: String? = nil,
        keepingDetailsOf previous: Ascent? = nil
    ) async throws {
        let before = results[problem.id]
        let attempts = attempts ?? previous?.attempts
        let perceived = perceivedGrade ?? previous?.perceivedGrade
        let limiters = limiters.isEmpty ? (previous?.limiters ?? []) : limiters
        let note = note ?? previous?.note
        // A flash is one attempt by definition.
        let cleanAttempts = result == .flash ? nil : attempts
        // Limiters only describe what stopped an unfinished project.
        let cleanLimiters = result == .project ? limiters : []

        // Optimistic update.
        if let result {
            results[problem.id] = Ascent(
                id: before?.id ?? UUID(),
                gymId: problem.gymId,
                problemId: problem.id,
                localDate: day,
                result: result,
                attempts: cleanAttempts,
                perceivedGrade: perceived,
                limiters: cleanLimiters,
                note: note,
                gradeIdSnapshot: before?.gradeIdSnapshot ?? problem.gradeId
            )
        } else {
            results[problem.id] = nil
        }
        saving.insert(problem.id)
        defer { saving.remove(problem.id) }

        do {
            try await backend.setAscent(
                problemId: problem.id,
                on: day,
                result: result,
                attempts: cleanAttempts,
                perceivedGrade: perceived,
                limiters: cleanLimiters,
                note: note
            )
            try await reloadDayThrowing()
        } catch {
            results[problem.id] = before
            throw error
        }
    }

    // MARK: Wellbeing

    func saveWellbeing(energy: Int?, rpe: Int?, skin: SkinState?, painAreas: Set<BodyArea>) async throws {
        let sessionId: UUID
        if let existing = session?.id {
            sessionId = existing
        } else {
            sessionId = try await backend.upsertSession(gymId: catalog.gym.id, on: day)
        }
        try await backend.setWellbeing(SessionWellbeing(
            sessionId: sessionId,
            energy: energy,
            rpe: rpe,
            skin: skin,
            painAreas: painAreas.sorted { $0.rawValue < $1.rawValue }
        ))
        try await reloadDayThrowing()
    }
}
