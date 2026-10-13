import Foundation
import Testing
@testable import BoulderKit

/// A plywood-colored test image with flat shapes drawn on it.
private struct Canvas {
    let width = 200
    let height = 150
    var pixels: [UInt8]

    init(background: (UInt8, UInt8, UInt8) = (215, 190, 160)) {
        pixels = []
        pixels.reserveCapacity(200 * 150 * 4)
        for _ in 0..<(200 * 150) { pixels += [background.0, background.1, background.2, 255] }
    }

    mutating func set(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) {
        let i = (y * width + x) * 4
        pixels[i] = c.0
        pixels[i + 1] = c.1
        pixels[i + 2] = c.2
    }

    mutating func disc(_ cx: Int, _ cy: Int, _ r: Int, _ c: (UInt8, UInt8, UInt8)) {
        for y in 0..<height {
            for x in 0..<width where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r { set(x, y, c) }
        }
    }

    mutating func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: (UInt8, UInt8, UInt8)) {
        for y in y0..<y1 { for x in x0..<x1 { set(x, y, c) } }
    }

    func detect() -> [DetectedHold] { HoldDetector.detect(rgba: pixels, width: width, height: height) }
}

@Suite("Hold detector")
struct HoldDetectorTests {
    @Test func findsHoldsByColorAndPlace() {
        var canvas = Canvas()
        canvas.disc(50, 50, 7, (60, 130, 50))
        canvas.disc(140, 90, 7, (200, 40, 40))
        let holds = canvas.detect()
        #expect(holds.count == 2)
        let green = holds.first { $0.color == .green }
        let red = holds.first { $0.color == .red }
        #expect(abs((green?.x ?? 0) * 200 - 50) < 1.5 && abs((green?.y ?? 0) * 150 - 50) < 1.5)
        #expect(abs((red?.x ?? 0) * 200 - 140) < 1.5 && abs((red?.y ?? 0) * 150 - 90) < 1.5)
        #expect(abs((red?.r ?? 0) * 200 - 7) < 1.5)
    }

    @Test func volumesAreNotHoldsButHoldsOnThemAre() {
        var canvas = Canvas()
        canvas.rect(60, 40, 140, 100, (40, 110, 125))
        canvas.disc(100, 70, 6, (235, 120, 40))
        let holds = canvas.detect()
        #expect(holds.map(\.color) == [.orange])
    }

    @Test func shadowsAreNotHolds() {
        var canvas = Canvas()
        canvas.rect(60, 40, 110, 90, (155, 137, 115))
        #expect(canvas.detect().isEmpty)
    }

    @Test func touchingHoldsOfTwoColorsStayTwo() {
        var canvas = Canvas()
        canvas.disc(90, 75, 8, (200, 40, 40))
        canvas.disc(105, 75, 7, (40, 70, 170))
        #expect(Set(canvas.detect().map(\.color)) == [.red, .blue])
    }

    @Test func everyHoldColor() {
        var canvas = Canvas()
        canvas.disc(60, 60, 8, (245, 245, 240))
        canvas.disc(140, 60, 8, (110, 60, 150))
        canvas.disc(100, 110, 7, (20, 20, 20))
        canvas.disc(40, 110, 7, (240, 200, 40))
        canvas.disc(160, 110, 7, (235, 110, 160))
        #expect(Set(canvas.detect().map(\.color)) == [.white, .purple, .black, .yellow, .pink])
    }

    @Test func specksAreIgnored() {
        var canvas = Canvas()
        canvas.disc(100, 75, 1, (200, 40, 40))
        #expect(canvas.detect().isEmpty)
    }
}

@Suite("Routes")
struct RouteTests {
    let photo = UUID()
    let sector = UUID()

    func hold(_ x: Double, _ y: Double, _ color: HoldColor?, r: Double = 0.02) -> PhotoHold {
        PhotoHold(photoId: photo, sectorId: sector, x: x, y: y, r: r, color: color, source: .auto)
    }

    @Test func tapsPickTheHoldUnderTheFinger() {
        let a = hold(0.20, 0.20, .green), b = hold(0.30, 0.20, .red)
        #expect(HoldMatching.hold(at: 0.21, 0.21, in: [a, b], aspect: 4 / 3)?.id == a.id)
        #expect(HoldMatching.hold(at: 0.50, 0.50, in: [a, b], aspect: 4 / 3) == nil)
    }

    @Test func nearestRespectsColorAndReach() {
        let green = hold(0.20, 0.20, .green), red = hold(0.22, 0.20, .red)
        #expect(HoldMatching.nearest(to: 0.21, 0.20, color: .green, in: [green, red], aspect: 4 / 3, maxDistance: 0.05)?.id == green.id)
        #expect(HoldMatching.nearest(to: 0.80, 0.80, color: .green, in: [green, red], aspect: 4 / 3, maxDistance: 0.05) == nil)
    }

    @Test func tapCycleBuildsARoute() {
        let a = UUID(), b = UUID()
        var route = RouteBuilding.tapped(a, in: [])
        #expect(route == [RouteStep(holdId: a, role: .hand)])
        route = RouteBuilding.tapped(a, in: route)
        #expect(route.first?.role == .start)
        route = RouteBuilding.tapped(b, in: route)
        route = RouteBuilding.tapped(b, in: route)
        route = RouteBuilding.tapped(b, in: route)
        #expect(route.map(\.role) == [.start, .top])
        #expect(RouteBuilding.isValid(route))
        route = RouteBuilding.tapped(b, in: route)
        #expect(route.map(\.holdId) == [a])
    }

    @Test func fullRolesAreSkipped() {
        let s1 = UUID(), s2 = UUID(), x = UUID()
        let route = [RouteStep(holdId: s1, role: .start), RouteStep(holdId: s2, role: .start), RouteStep(holdId: x, role: .hand)]
        #expect(RouteBuilding.tapped(x, in: route).last?.role == .top)
        #expect(!RouteBuilding.isValid([RouteStep(holdId: x, role: .hand)]))
        #expect(RouteBuilding.isValid([]))
    }

    @Test func routesCarryOverToTheNearestHoldOfTheirColor() {
        let problem = UUID(), oldPhoto = UUID()
        let old = [
            RouteHold(problemId: problem, holdId: UUID(), role: .start, photoId: oldPhoto, x: 0.20, y: 0.80, r: 0.02, color: .green),
            RouteHold(problemId: problem, holdId: UUID(), role: .top, photoId: oldPhoto, x: 0.40, y: 0.20, r: 0.02, color: .green),
        ]
        let start = hold(0.21, 0.79, .green), top = hold(0.41, 0.21, .green), red = hold(0.20, 0.80, .red)
        let carried = HoldMatching.carryOver(old, onto: [red, start, top], aspect: 4 / 3)
        #expect(carried.steps == [RouteStep(holdId: start.id, role: .start), RouteStep(holdId: top.id, role: .top)])
        #expect(!carried.needsReview)

        let lost = HoldMatching.carryOver(old, onto: [red, top], aspect: 4 / 3)
        #expect(lost.steps.isEmpty && lost.needsReview)
    }
}

@Suite("Freshness")
struct FreshnessTests {
    let warsaw = TimeZone(identifier: "Europe/Warsaw")!

    func problem(setAt: String, changedAt: String? = nil, kind: ChangeKind? = nil) -> ActiveProblem {
        ActiveProblem(id: UUID(), gymId: UUID(), sectorId: UUID(), gradeId: UUID(), holdColor: .green,
                      setAt: try! Date(setAt, strategy: .iso8601), photoId: UUID(), pinX: 0.5, pinY: 0.5,
                      changedAt: changedAt.map { try! Date($0, strategy: .iso8601) }, changeKind: kind)
    }

    @Test func newAndChangedSinceTheLastVisit() {
        let visit = LocalDate("2026-10-05")
        let now = try! Date("2026-10-13T10:00:00Z", strategy: .iso8601)
        #expect(Freshness.of(problem(setAt: "2026-10-08T10:00:00Z"), lastVisit: visit, now: now, timeZone: warsaw) == .new)
        let regraded = problem(setAt: "2026-09-01T10:00:00Z", changedAt: "2026-10-07T10:00:00Z", kind: .grade)
        #expect(Freshness.of(regraded, lastVisit: visit, now: now, timeZone: warsaw)
                == .changed(.grade, at: try! Date("2026-10-07T10:00:00Z", strategy: .iso8601)))
        let old = problem(setAt: "2026-09-01T10:00:00Z", changedAt: "2026-10-01T10:00:00Z", kind: .route)
        #expect(Freshness.of(old, lastVisit: visit, now: now, timeZone: warsaw) == nil)
    }

    @Test func withoutAVisitAMarkLastsAWeek() {
        let now = try! Date("2026-10-13T10:00:00Z", strategy: .iso8601)
        let fresh = problem(setAt: "2026-09-01T10:00:00Z", changedAt: "2026-10-10T10:00:00Z", kind: .route)
        let stale = problem(setAt: "2026-09-01T10:00:00Z", changedAt: "2026-10-01T10:00:00Z", kind: .route)
        #expect(Freshness.of(fresh, lastVisit: nil, now: now, timeZone: warsaw) != nil)
        #expect(Freshness.of(stale, lastVisit: nil, now: now, timeZone: warsaw) == nil)
    }

    @Test func changedAfterMyTop() {
        let p = problem(setAt: "2026-09-01T10:00:00Z", changedAt: "2026-10-07T10:00:00Z", kind: .route)
        #expect(Freshness.changedSince(p, toppedOn: LocalDate("2026-10-02")!, timeZone: warsaw))
        #expect(!Freshness.changedSince(p, toppedOn: LocalDate("2026-10-09")!, timeZone: warsaw))
    }

    @Test func newSinceFilterIncludesChangedProblems() {
        let p = problem(setAt: "2026-09-01T10:00:00Z", changedAt: "2026-10-07T10:00:00Z", kind: .grade)
        let filter = ProblemFilter(setAfter: LocalDate("2026-10-05"))
        #expect(filter.matches(p, grades: [:], toppedProblemIds: [], timeZone: warsaw))
        let untouched = problem(setAt: "2026-09-01T10:00:00Z")
        #expect(!filter.matches(untouched, grades: [:], toppedProblemIds: [], timeZone: warsaw))
    }

    @Test func rowsDecodeWithAndWithoutFreshness() throws {
        let base = """
        {"id":"8b1f3f4e-0000-4000-8000-000000000001","gym_id":"8b1f3f4e-0000-4000-8000-000000000002",
         "sector_id":"8b1f3f4e-0000-4000-8000-000000000003","grade_id":"8b1f3f4e-0000-4000-8000-000000000004",
         "hold_color":"green","name":null,"style_tags":[],"set_at":"2026-10-01T10:00:00Z",
         "photo_id":"8b1f3f4e-0000-4000-8000-000000000005","pin_x":0.2,"pin_y":0.8
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plain = try decoder.decode(ActiveProblem.self, from: Data((base + "}").utf8))
        #expect(plain.changedAt == nil && plain.changeKind == nil)
        let changed = try decoder.decode(ActiveProblem.self, from: Data((base + #","changed_at":"2026-10-07T10:00:00Z","change_kind":"both"}"#).utf8))
        #expect(changed.changeKind == .both && changed.changedAt != nil)

        let route = try decoder.decode(RouteHold.self, from: Data("""
        {"problem_id":"8b1f3f4e-0000-4000-8000-000000000001","hold_id":"8b1f3f4e-0000-4000-8000-000000000006",
         "role":"start","photo_id":"8b1f3f4e-0000-4000-8000-000000000005","x":0.2,"y":0.8,"r":0.02,"color":null}
        """.utf8))
        #expect(route.role == .start && route.color == nil)
    }
}
