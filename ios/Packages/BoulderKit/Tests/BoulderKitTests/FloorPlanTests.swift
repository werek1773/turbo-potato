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

    @Test func tapInsideAFieldPicksItsSector() {
        // Volt's Dziób: the wall bends inwards, so the field is concave.
        let dziob = [MapPoint(x: 0.7999, y: 0.5217), MapPoint(x: 0.7212, y: 0.5925), MapPoint(x: 0.8087, y: 0.6349),
                     MapPoint(x: 0.5125, y: 0.6321), MapPoint(x: 0.5625, y: 0.5189)]
        #expect(PlanGeometry.contains(MapPoint(x: 0.62, y: 0.57), in: dziob))
        // In the notch of the bend: outside the field, on the open floor.
        #expect(!PlanGeometry.contains(MapPoint(x: 0.78, y: 0.59), in: dziob))
        #expect(!PlanGeometry.contains(MapPoint(x: 0.4, y: 0.57), in: dziob))
        #expect(!PlanGeometry.contains(MapPoint(x: 0.5, y: 0.5), in: [MapPoint(x: 0, y: 0), MapPoint(x: 1, y: 1)]))
    }

    @Test func sectorDecodesItsField() throws {
        let json = #"{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "gym_id": "6F9619FF-8B86-D011-B42D-00C04FC964FE", "name": "Połóg", "sort_order": 7, "map_path": [[0.4, 0.88], [0.19, 0.88]], "map_zone": [[0.4, 0.88], [0.19, 0.88], [0.28, 0.77]]}"#
        let sector = try JSONDecoder().decode(Sector.self, from: Data(json.utf8))
        #expect(sector.mapZone?.count == 3)
        #expect(sector.mapZone?.last == MapPoint(x: 0.28, y: 0.77))
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
