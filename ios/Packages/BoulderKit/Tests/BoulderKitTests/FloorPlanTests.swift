import Foundation
import Testing
@testable import BoulderKit

@Suite("Floor plan")
struct FloorPlanTests {
    @Test func decodesTheDatabaseShape() throws {
        let json = #"{"aspect": 0.75, "walls": [[[0.1, 0.2], [0.3, 0.2]]], "labels": [{"text": "Mała sala", "x": 0.5, "y": 0.2}]}"#
        let plan = try JSONDecoder().decode(FloorPlan.self, from: Data(json.utf8))
        #expect(plan.aspect == 0.75)
        #expect(plan.walls[0][1] == MapPoint(x: 0.3, y: 0.2))
        #expect(plan.outlines.isEmpty)
        #expect(plan.labels[0].text == "Mała sala")
    }

    @Test func tapPicksTheClosestWall() {
        let paths: [(id: String, points: [MapPoint])] = [
            ("Połóg", [MapPoint(x: 0, y: 0), MapPoint(x: 100, y: 0)]),
            ("Trójkąt", [MapPoint(x: 100, y: 0), MapPoint(x: 150, y: 50)]),
        ]
        #expect(PlanGeometry.nearest(to: MapPoint(x: 50, y: 10), among: paths, maxDistance: 24) == "Połóg")
        #expect(PlanGeometry.nearest(to: MapPoint(x: 130, y: 25), among: paths, maxDistance: 24) == "Trójkąt")
        #expect(PlanGeometry.nearest(to: MapPoint(x: 50, y: 80), among: paths, maxDistance: 24) == nil)
    }

    @Test func midpointFollowsThePolyline() {
        let path = [MapPoint(x: 0, y: 0), MapPoint(x: 10, y: 0), MapPoint(x: 10, y: 10)]
        #expect(PlanGeometry.midpoint(of: path) == MapPoint(x: 10, y: 0))
    }
}
