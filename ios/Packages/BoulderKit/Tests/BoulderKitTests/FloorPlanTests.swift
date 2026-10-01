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

    @Test func decodesMatsAndEntrances() throws {
        let json = #"{"aspect": 1, "mats": [[[0, 0], [1, 0], [1, 1]]], "entrances": [[0.5, 0.9]]}"#
        let plan = try JSONDecoder().decode(FloorPlan.self, from: Data(json.utf8))
        #expect(plan.mats[0].count == 3)
        #expect(plan.entrances == [MapPoint(x: 0.5, y: 0.9)])
        #expect(plan.labels.isEmpty)
    }

    @Test func jointsMarkWhereWallsMeet() {
        // Three sectors end to end, along the top and down past a corner; a
        // wall standing apart and a stray single point add nothing.
        let lines = [
            [MapPoint(x: 0, y: 0), MapPoint(x: 10, y: 0)],
            [MapPoint(x: 10, y: 0), MapPoint(x: 20, y: 0), MapPoint(x: 20, y: 10)],
            [MapPoint(x: 20, y: 10), MapPoint(x: 20, y: 20)],
            [MapPoint(x: 40, y: 0), MapPoint(x: 50, y: 0)],
            [MapPoint(x: 10, y: 0)],
        ]
        let joints = PlanGeometry.joints(of: lines, tolerance: 0.5)
        #expect(joints.map { $0.point } == [MapPoint(x: 10, y: 0), MapPoint(x: 20, y: 10)])
        // The tick crosses the wall: upright on the top, level on the side.
        #expect(joints.map { $0.across } == [MapPoint(x: 0, y: -1), MapPoint(x: 1, y: 0)])
    }

    @Test func aCornerJointTicksAlongTheBisector() throws {
        // Ends a hair apart still meet.
        let lines = [
            [MapPoint(x: 0, y: 0), MapPoint(x: 10, y: 0)],
            [MapPoint(x: 10, y: 0.2), MapPoint(x: 10, y: 10)],
        ]
        let joint = try #require(PlanGeometry.joints(of: lines, tolerance: 0.5).first)
        #expect(joint.point == MapPoint(x: 10, y: 0))
        #expect(abs(abs(joint.across.x) - 0.5.squareRoot()) < 1e-9)
        #expect(abs(abs(joint.across.y) - 0.5.squareRoot()) < 1e-9)
    }

    @Test func pointsAlongAWallFaceTheFloor() throws {
        // A wall walked left to right along the top: the floor is below it.
        let wall = [MapPoint(x: 0, y: 0), MapPoint(x: 10, y: 0), MapPoint(x: 10, y: 10)]
        let quarter = try #require(PlanGeometry.point(along: wall, at: 0.25))
        #expect(quarter.point == MapPoint(x: 5, y: 0))
        #expect(quarter.normal == MapPoint(x: -0.0, y: 1))
        let end = try #require(PlanGeometry.point(along: wall, at: 1.4))
        #expect(end.point == MapPoint(x: 10, y: 10))
        #expect(end.normal == MapPoint(x: -1, y: 0))
        #expect(PlanGeometry.point(along: [MapPoint(x: 1, y: 1)], at: 0.5) == nil)
    }
}
