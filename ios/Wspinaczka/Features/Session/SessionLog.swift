import BoulderKit
import Foundation
import Observation

/// State of "Podsumuj sesję" for one gym and one climbing day.
///
/// Every change is shown at once and queued in the `JournalOutbox`, which
/// sends it when there is network; nothing here waits for the server.
@MainActor
@Observable
final class SessionLog {
    let catalog: GymCatalog
    let outbox: JournalOutbox
    var day: LocalDate {
        didSet {
            guard oldValue != day else { return }
            serverWellbeing = nil
            Task { await reloadDay() }
        }
    }

    /// My wellbeing entry of the day as confirmed by the server.
    private var serverWellbeing: WellbeingValues?
    /// Why the last refresh from the server failed (shown, not thrown).
    private(set) var loadError: String?
    private(set) var isLoadErrorConnectivity = false

    init(catalog: GymCatalog, day: LocalDate, outbox: JournalOutbox = .shared) {
        self.catalog = catalog
        self.day = day
        self.outbox = outbox
    }

    var backend: Backend { catalog.backend }
    var today: LocalDate { catalog.today }

    /// My records of this day, by problem (pending writes included).
    var results: [UUID: Ascent] {
        Dictionary(
            catalog.myAscents.filter { $0.localDate == day }.map { ($0.problemId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var dayAscents: [Ascent] { Array(results.values) }

    var summary: DaySummary { DaySummary.of(dayAscents, grades: catalog.gradesById) }

    /// The day's wellbeing: a pending save wins over the server's entry.
    var wellbeing: WellbeingValues? {
        if let pending = outbox.pendingWellbeing(gymId: catalog.gym.id, on: day) {
            return pending.values.isEmpty ? nil : pending.values
        }
        return serverWellbeing
    }

    /// Problems tried on an earlier day cannot be flashed today.
    var flashable: Set<UUID> {
        DaySummary.flashableProblemIds(
            problemIds: catalog.problems.map(\.id),
            history: catalog.myAscents,
            day: day
        )
    }

    // MARK: Loading

    /// Shows the cached catalog at once, then refreshes it from the server.
    func load() async {
        await refresh {
            try await self.catalog.load()
            try await self.loadWellbeing()
        }
    }

    func reloadDay() async {
        await refresh { try await self.loadWellbeing() }
    }

    /// Brings my ascents in line with the server once the outbox is sent
    /// (the server may have changed them, e.g. a later flash became a top).
    func reconcile() async {
        await refresh {
            try await self.catalog.refreshMyAscents()
            try await self.loadWellbeing()
        }
    }

    private func refresh(_ work: () async throws -> Void) async {
        do {
            try await work()
            loadError = nil
            isLoadErrorConnectivity = false
        } catch {
            // A view's .task cancelled mid-request is not a failure.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            loadError = UserFacingError.message(for: error)
            isLoadErrorConnectivity = error.isConnectivityError
        }
    }

    private func loadWellbeing() async throws {
        let requestedDay = day
        let session = try await backend.session(gymId: catalog.gym.id, on: requestedDay)
        let entry: SessionWellbeing? = if let session {
            try await backend.wellbeing(sessionId: session.id)
        } else {
            nil
        }
        // A save made meanwhile is newer than what was downloaded.
        guard requestedDay == day, outbox.pendingWellbeing(gymId: catalog.gym.id, on: day) == nil else { return }
        serverWellbeing = entry.map(WellbeingValues.init)
    }

    // MARK: Pins

    /// Tap on a pin: none → top → flash → project → none.
    func cycle(_ problem: ActiveProblem) {
        let current = results[problem.id]
        let next = AscentResult.next(after: current?.result, canFlash: flashable.contains(problem.id))
        set(problem, result: next, keepingDetailsOf: current)
    }

    func set(
        _ problem: ActiveProblem,
        result: AscentResult?,
        attempts: AttemptsBucket? = nil,
        perceivedGrade: PerceivedGrade? = nil,
        limiters: [Limiter] = [],
        note: String? = nil,
        keepingDetailsOf previous: Ascent? = nil
    ) {
        let attempts = attempts ?? previous?.attempts
        let perceived = perceivedGrade ?? previous?.perceivedGrade
        let limiters = limiters.isEmpty ? (previous?.limiters ?? []) : limiters
        let note = note ?? previous?.note

        let write = PendingAscent(
            id: results[problem.id]?.id ?? UUID(),
            gymId: problem.gymId,
            problemId: problem.id,
            localDate: day,
            result: result,
            // A flash is one attempt by definition.
            attempts: result == .flash ? nil : attempts,
            perceivedGrade: perceived,
            // Limiters only describe what stopped an unfinished project.
            limiters: result == .project ? limiters : [],
            note: note,
            gradeIdSnapshot: problem.gradeId
        )
        catalog.applyLocal(write)
        outbox.enqueue(.ascent(write))
    }

    // MARK: Wellbeing

    func saveWellbeing(energy: Int?, rpe: Int?, skin: SkinState?, painAreas: Set<BodyArea>) {
        let values = WellbeingValues(
            energy: energy,
            rpe: rpe,
            skin: skin,
            painAreas: painAreas.sorted { $0.rawValue < $1.rawValue }
        )
        // What the server will hold once sent, so nothing jumps back then.
        serverWellbeing = values.isEmpty ? nil : values
        outbox.enqueue(.wellbeing(PendingWellbeing(gymId: catalog.gym.id, localDate: day, values: values)))
    }
}
