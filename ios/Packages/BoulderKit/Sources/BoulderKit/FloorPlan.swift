import Foundation

/// A point on a floor plan, normalized to 0...1 (x to the right, y down).
/// Encoded as `[x, y]`.
public struct MapPoint: Hashable, Sendable, Codable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

/// The gym drawn like its own reset board: mats, walls and entrances.
public struct FloorPlan: Hashable, Sendable, Codable {
    public struct Label: Hashable, Sendable, Codable {
        public let text: String
        public let x: Double
        public let y: Double
    }

    /// Width / height of the plan.
    public let aspect: Double
    /// Climbing wall that belongs to no sector (unlabeled on the reset
    /// board); drawn like the rest of the wall.
    public let walls: [[MapPoint]]
    /// Floor edges and room boundaries, drawn faintly.
    public let outlines: [[MapPoint]]
    /// Closed polygons of matted floor under the walls, filled softly.
    public let mats: [[MapPoint]]
    /// Doors, drawn as green dots like on the reset board.
    public let entrances: [MapPoint]
    public let labels: [Label]

    public init(aspect: Double, walls: [[MapPoint]] = [], outlines: [[MapPoint]] = [],
                mats: [[MapPoint]] = [], entrances: [MapPoint] = [], labels: [Label] = []) {
        self.aspect = aspect
        self.walls = walls
        self.outlines = outlines
        self.mats = mats
        self.entrances = entrances
        self.labels = labels
    }

    enum CodingKeys: String, CodingKey {
        case aspect, walls, outlines, mats, entrances, labels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aspect = try container.decode(Double.self, forKey: .aspect)
        walls = try container.decodeIfPresent([[MapPoint]].self, forKey: .walls) ?? []
        outlines = try container.decodeIfPresent([[MapPoint]].self, forKey: .outlines) ?? []
        mats = try container.decodeIfPresent([[MapPoint]].self, forKey: .mats) ?? []
        entrances = try container.decodeIfPresent([MapPoint].self, forKey: .entrances) ?? []
        labels = try container.decodeIfPresent([Label].self, forKey: .labels) ?? []
    }
}

public enum PlanGeometry {
    /// Distance from `point` to a polyline, in the same units as the input.
    public static func distance(from point: MapPoint, to polyline: [MapPoint]) -> Double {
        guard let first = polyline.first else { return .infinity }
        guard polyline.count > 1 else { return hypot(point.x - first.x, point.y - first.y) }
        return zip(polyline, polyline.dropFirst())
            .map { segmentDistance(point, $0, $1) }
            .min() ?? .infinity
    }

    private static func segmentDistance(_ p: MapPoint, _ a: MapPoint, _ b: MapPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// The sector whose wall is closest to a tap, if within `maxDistance`.
    /// Points are in view coordinates (already scaled by the view size).
    public static func nearest<ID>(
        to tap: MapPoint,
        among paths: [(id: ID, points: [MapPoint])],
        maxDistance: Double
    ) -> ID? {
        paths
            .map { (id: $0.id, distance: distance(from: tap, to: $0.points)) }
            .filter { $0.distance <= maxDistance }
            .min { $0.distance < $1.distance }?
            .id
    }

    /// A point at `fraction` (0...1) of the polyline's length, with the unit
    /// normal pointing to the right of the walking direction. Sector paths
    /// run so that the floor is on their right: a photo's left edge is the
    /// path's start, so a pin's x maps straight onto the fraction.
    public static func point(along polyline: [MapPoint], at fraction: Double) -> (point: MapPoint, normal: MapPoint)? {
        let segments = zip(polyline, polyline.dropFirst())
            .map { (a: $0, b: $1, length: hypot($1.x - $0.x, $1.y - $0.y)) }
            .filter { $0.length > 0 }
        guard !segments.isEmpty else { return nil }
        var remaining = max(0, min(1, fraction)) * segments.reduce(0) { $0 + $1.length }
        for (index, segment) in segments.enumerated() {
            if remaining <= segment.length || index == segments.count - 1 {
                let t = min(1, remaining / segment.length)
                let dx = (segment.b.x - segment.a.x) / segment.length
                let dy = (segment.b.y - segment.a.y) / segment.length
                return (MapPoint(x: segment.a.x + dx * segment.length * t, y: segment.a.y + dy * segment.length * t),
                        MapPoint(x: -dy, y: dx))
            }
            remaining -= segment.length
        }
        return nil
    }

    /// Midpoint along the polyline's length (for labels).
    public static func midpoint(of polyline: [MapPoint]) -> MapPoint? {
        guard let first = polyline.first else { return nil }
        let segments = Array(zip(polyline, polyline.dropFirst()))
        let lengths = segments.map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return first }
        var remaining = total / 2
        for (index, segment) in segments.enumerated() {
            if remaining <= lengths[index] {
                let t = remaining / lengths[index]
                return MapPoint(x: segment.0.x + t * (segment.1.x - segment.0.x),
                                y: segment.0.y + t * (segment.1.y - segment.0.y))
            }
            remaining -= lengths[index]
        }
        return polyline.last
    }
}
