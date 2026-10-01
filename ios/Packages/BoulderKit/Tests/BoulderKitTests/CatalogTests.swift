import Foundation
import Testing
@testable import BoulderKit

@Suite("Catalog")
struct CatalogTests {
    let gym = UUID()
    let grotto = UUID()
    let slab = UUID()
    let photo = UUID()
    let warsaw = TimeZone(identifier: "Europe/Warsaw")!

    var grades: [Grade] {
        (1...9).map { Grade(id: UUID(uuidString: "00000000-0000-4000-8000-00000000000\($0)")!, gymId: gym, label: "\($0)", sortOrder: $0) }
    }

    func problem(grade: Int, sector: UUID, color: HoldColor, setAt: String = "2026-09-20T10:00:00Z") -> ActiveProblem {
        ActiveProblem(id: UUID(), gymId: gym, sectorId: sector, gradeId: grades[grade - 1].id,
                      holdColor: color, setAt: try! Date(setAt, strategy: .iso8601),
                      photoId: photo, pinX: 0.5, pinY: 0.5)
    }

    @Test func filtersCombine() {
        let fourGrotto = problem(grade: 4, sector: grotto, color: .yellow)
        let fourSlab = problem(grade: 4, sector: slab, color: .blue)
        let sixGrotto = problem(grade: 6, sector: grotto, color: .yellow)
        let all = [fourGrotto, fourSlab, sixGrotto]
        let lookup = Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0) })

        let onlyFours = ProblemFilter(gradeOrders: 4...4)
        #expect(onlyFours.apply(to: all, grades: lookup, toppedProblemIds: [], timeZone: warsaw) == [fourGrotto, fourSlab])

        let foursNotDone = ProblemFilter(gradeOrders: 4...4, onlyNotTopped: true)
        #expect(foursNotDone.apply(to: all, grades: lookup, toppedProblemIds: [fourGrotto.id], timeZone: warsaw) == [fourSlab])

        let grottoYellow = ProblemFilter(sectorIds: [grotto], colors: [.yellow])
        #expect(grottoYellow.apply(to: all, grades: lookup, toppedProblemIds: [], timeZone: warsaw) == [fourGrotto, sixGrotto])
    }

    @Test func newSinceLastVisitUsesClimbingDays() {
        let lookup = Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0) })
        let old = problem(grade: 3, sector: grotto, color: .red, setAt: "2026-09-20T10:00:00Z")
        let fresh = problem(grade: 3, sector: grotto, color: .red, setAt: "2026-09-25T10:00:00Z")
        let filter = ProblemFilter(setAfter: LocalDate("2026-09-22"))
        #expect(filter.apply(to: [old, fresh], grades: lookup, toppedProblemIds: [], timeZone: warsaw) == [fresh])
    }

    @Test func coverageCountsActiveProblemsPerGrade() {
        let a = problem(grade: 4, sector: grotto, color: .yellow)
        let b = problem(grade: 4, sector: slab, color: .blue)
        let c = problem(grade: 5, sector: slab, color: .green)
        let coverage = Coverage.byGrade(problems: [a, b, c], grades: grades, toppedProblemIds: [a.id])
        #expect(coverage.map(\.grade.label) == ["4", "5"])
        #expect(coverage[0].active == 2 && coverage[0].topped == 1)
        #expect(coverage[1].fraction == 0)
    }

    @Test func tapCycle() {
        #expect(AscentResult.next(after: nil) == .top)
        #expect(AscentResult.next(after: .top) == .flash)
        #expect(AscentResult.next(after: .flash) == .project)
        #expect(AscentResult.next(after: .project) == nil)
    }

    @Test func inviteCodesMatchTheDatabaseNormalization() {
        #expect(InviteCode.normalize("ab1o-k9i l-zz") == "AB10K91" + "1ZZ")
        #expect(InviteCode.isComplete("7KQ2-M9XA-T4BC"))
        #expect(!InviteCode.isComplete("7KQ2-M9XA"))
        #expect(InviteCode.formatted("7kq2m9xat4bc") == "7KQ2-M9XA-T4BC")
    }

    @Test func inviteLinksRoundTrip() {
        let url = InviteCode.url(for: "7kq2m9xat4bc")
        #expect(url.absoluteString == "wspinaczka://invite?code=7KQ2-M9XA-T4BC")
        #expect(InviteCode.code(from: url) == "7KQ2-M9XA-T4BC")
        #expect(InviteCode.code(from: URL(string: "https://example.com/invite?code=X")!) == nil)
    }
}
