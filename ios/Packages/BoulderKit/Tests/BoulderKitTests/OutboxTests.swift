import Foundation
import Testing
@testable import BoulderKit

@Suite("Outbox")
struct OutboxTests {
    let me = UUID()
    let someoneElse = UUID()
    let gym = UUID()
    let otherGym = UUID()
    let grade = UUID()
    let problem = UUID()
    let otherProblem = UUID()
    let day = LocalDate("2026-10-07")!
    /// Fixed so that writes compare equal by content.
    let localId = UUID()

    func tap(_ problemId: UUID, _ result: AscentResult?, on date: LocalDate? = nil, gym: UUID? = nil) -> PendingWrite {
        .ascent(PendingAscent(id: localId, gymId: gym ?? self.gym, problemId: problemId, localDate: date ?? day,
                              result: result, gradeIdSnapshot: grade))
    }

    func serverAscent(_ problemId: UUID, _ result: AscentResult, on date: LocalDate? = nil) -> Ascent {
        Ascent(gymId: gym, problemId: problemId, localDate: date ?? day, result: result, gradeIdSnapshot: grade)
    }

    @Test func repeatedTapsOnOneProblemKeepOnlyTheFinalState() {
        var outbox = Outbox()
        outbox.enqueue(tap(problem, .top), userId: me)
        outbox.enqueue(tap(otherProblem, .top), userId: me)
        outbox.enqueue(tap(problem, .flash), userId: me)
        outbox.enqueue(tap(problem, .project), userId: me)

        #expect(outbox.entries.count == 2)
        // The latest tap goes to the back of the queue.
        #expect(outbox.entries.map(\.write) == [tap(otherProblem, .top), tap(problem, .project)])
    }

    @Test func sameProblemOnAnotherDayIsAnotherWrite() {
        var outbox = Outbox()
        outbox.enqueue(tap(problem, .top), userId: me)
        outbox.enqueue(tap(problem, .top, on: day.adding(days: -1)), userId: me)
        #expect(outbox.entries.count == 2)
    }

    @Test func wellbeingOfADayCoalesces() {
        var outbox = Outbox()
        let first = PendingWellbeing(gymId: gym, localDate: day, values: WellbeingValues(energy: 2))
        let second = PendingWellbeing(gymId: gym, localDate: day, values: WellbeingValues(energy: 4, rpe: 7))
        outbox.enqueue(.wellbeing(first), userId: me)
        outbox.enqueue(tap(problem, .top), userId: me)
        outbox.enqueue(.wellbeing(second), userId: me)

        #expect(outbox.entries.count == 2)
        #expect(outbox.pendingWellbeing(userId: me, gymId: gym, on: day) == second)
        #expect(outbox.pendingWellbeing(userId: me, gymId: gym, on: day.adding(days: -1)) == nil)
    }

    @Test func removingAnInFlightEntryKeepsTheNewerTap() {
        var outbox = Outbox()
        let inFlight = outbox.enqueue(tap(problem, .top), userId: me)
        // Tapped again while the first write was being sent.
        let newer = outbox.enqueue(tap(problem, .flash), userId: me)
        outbox.remove(id: inFlight.id)

        #expect(outbox.entries.map(\.id) == [newer.id])
        #expect(outbox.next(for: me)?.write == tap(problem, .flash))
    }

    @Test func entriesAreScopedToTheirUser() {
        var outbox = Outbox()
        outbox.enqueue(tap(problem, .top), userId: someoneElse)
        outbox.enqueue(tap(problem, .flash), userId: me)

        #expect(outbox.entries.count == 2)
        #expect(outbox.next(for: me)?.write == tap(problem, .flash))
        #expect(outbox.pendingAscents(userId: me, gymId: gym).map(\.result) == [.flash])

        outbox.removeAll(notBelongingTo: me)
        #expect(outbox.entries.allSatisfy { $0.userId == me })
    }

    @Test func pendingAscentsAreFilteredByGym() {
        var outbox = Outbox()
        outbox.enqueue(tap(problem, .top), userId: me)
        outbox.enqueue(tap(otherProblem, .top, gym: otherGym), userId: me)
        #expect(outbox.pendingAscents(userId: me, gymId: gym).map(\.problemId) == [problem])
    }

    @Test func failuresAreCountedAndReplacingClearsTheError() {
        var outbox = Outbox()
        let entry = outbox.enqueue(tap(problem, .flash), userId: me)
        outbox.recordFailure(id: entry.id, message: "offline")
        outbox.recordFailure(id: entry.id, message: "offline")
        #expect(outbox.entries[0].failures == 2)
        #expect(outbox.entries[0].lastError == "offline")

        outbox.replace(id: entry.id, with: tap(problem, .top))
        #expect(outbox.entries[0].write == tap(problem, .top))
        #expect(outbox.entries[0].lastError == nil)
    }

    @Test func survivesARoundTripThroughJSON() throws {
        var outbox = Outbox()
        outbox.enqueue(.ascent(PendingAscent(
            gymId: gym, problemId: problem, localDate: day, result: .project,
            attempts: .fourToTen, perceivedGrade: .hard, limiters: [.power, .beta],
            note: "lewa noga", gradeIdSnapshot: grade
        )), userId: me)
        outbox.enqueue(tap(otherProblem, nil), userId: me)
        outbox.enqueue(.wellbeing(PendingWellbeing(
            gymId: gym, localDate: day,
            values: WellbeingValues(energy: 3, rpe: 8, skin: .thin, painAreas: [.fingers])
        )), userId: me)

        let data = try JSONEncoder().encode(outbox)
        #expect(try JSONDecoder().decode(Outbox.self, from: data) == outbox)
    }

    // MARK: Merge

    @Test func pendingTapOverridesTheServerRecord() {
        let server = [serverAscent(problem, .top), serverAscent(otherProblem, .flash)]
        let pending = [PendingAscent(gymId: gym, problemId: problem, localDate: day, result: .project,
                                     limiters: [.power], gradeIdSnapshot: UUID())]
        let merged = Outbox.merge(server: server, pending: pending)

        let record = merged.first { $0.problemId == problem }
        #expect(merged.count == 2)
        #expect(record?.result == .project)
        #expect(record?.limiters == [.power])
        // Identity and the grade snapshot stay those of the server row.
        #expect(record?.id == server[0].id)
        #expect(record?.gradeIdSnapshot == grade)
    }

    @Test func pendingClearRemovesTheServerRecord() {
        let server = [serverAscent(problem, .top), serverAscent(otherProblem, .flash)]
        let merged = Outbox.merge(server: server, pending: [
            PendingAscent(gymId: gym, problemId: problem, localDate: day, result: nil, gradeIdSnapshot: grade),
        ])
        #expect(merged.map(\.problemId) == [otherProblem])
    }

    @Test func pendingTapOnANewProblemIsAdded() {
        let yesterday = day.adding(days: -1)
        let server = [serverAscent(otherProblem, .top, on: yesterday)]
        let merged = Outbox.merge(server: server, pending: [
            PendingAscent(gymId: gym, problemId: problem, localDate: day, result: .flash, gradeIdSnapshot: grade),
            PendingAscent(gymId: gym, problemId: otherProblem, localDate: day, result: nil, gradeIdSnapshot: grade),
        ])
        // Newest day first; clearing a record the server never had is a no-op.
        #expect(merged.map(\.localDate) == [day, yesterday])
        #expect(merged.first?.result == .flash)
    }

    @Test func otherDaysOfTheSameProblemAreUntouched() {
        let yesterday = day.adding(days: -1)
        let server = [serverAscent(problem, .top, on: yesterday)]
        let merged = Outbox.merge(server: server, pending: [
            PendingAscent(gymId: gym, problemId: problem, localDate: day, result: .top, gradeIdSnapshot: grade),
        ])
        #expect(merged.count == 2)
    }

    @Test func mergeWithoutPendingReturnsTheServerState() {
        let server = [serverAscent(problem, .top)]
        #expect(Outbox.merge(server: server, pending: []) == server)
    }

    // MARK: Backoff

    @Test func retryDelayGrowsAndIsCapped() {
        #expect(Outbox.retryDelay(afterFailures: 0) == .zero)
        #expect(Outbox.retryDelay(afterFailures: 1) == .seconds(2))
        #expect(Outbox.retryDelay(afterFailures: 2) == .seconds(4))
        #expect(Outbox.retryDelay(afterFailures: 5) == .seconds(32))
        #expect(Outbox.retryDelay(afterFailures: 9) == .seconds(300))
        #expect(Outbox.retryDelay(afterFailures: 1000) == .seconds(300))
    }
}

@Suite("Catalog snapshot")
struct CatalogSnapshotTests {
    @Test func survivesARoundTripThroughJSON() throws {
        let gym = UUID()
        let sector = Sector(id: UUID(), gymId: gym, name: "Grota", area: "Duża sala", sortOrder: 1,
                            currentPhotoId: UUID(), lastResetAt: Date(timeIntervalSince1970: 1_790_000_000),
                            nextResetOn: LocalDate("2026-10-20"),
                            mapPath: [MapPoint(x: 0.1, y: 0.2), MapPoint(x: 0.3, y: 0.2)])
        let photo = SectorPhoto(id: sector.currentPhotoId!, sectorId: sector.id, gymId: gym,
                                storagePath: "\(gym)/\(sector.id)/a.jpg", width: 1600, height: 1200)
        let grade = Grade(id: UUID(), gymId: gym, label: "5", sortOrder: 5, color: "#f00")
        let problem = ActiveProblem(id: UUID(), gymId: gym, sectorId: sector.id, gradeId: grade.id,
                                    holdColor: .blue, styleTags: [.crimps],
                                    setAt: Date(timeIntervalSince1970: 1_790_100_000),
                                    photoId: photo.id, pinX: 0.4, pinY: 0.6)
        let ascent = Ascent(gymId: gym, problemId: problem.id, localDate: LocalDate("2026-10-07")!,
                            result: .top, attempts: .twoToThree, gradeIdSnapshot: grade.id)
        let snapshot = CatalogSnapshot(gymId: gym, grades: [grade], sectors: [sector], photos: [photo],
                                       problems: [problem], myAscents: [ascent])

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CatalogSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.isCurrent)
    }
}
