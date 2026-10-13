import Foundation

/// Finding holds near a point, and carrying routes over to a new photo.
/// Distances are in shares of the photo's width; `aspect` is width / height,
/// so a y difference (a share of the height) counts as dy / aspect.
public enum HoldMatching {
    static func distance(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, aspect: Double) -> Double {
        hypot(ax - bx, (ay - by) / aspect)
    }

    /// The hold under a tap: the nearest one whose circle (with a little
    /// slack for fingers) contains the point.
    public static func hold(at x: Double, _ y: Double, in holds: [PhotoHold], aspect: Double,
                            slack: Double = 0.012) -> PhotoHold? {
        holds
            .map { (hold: $0, d: distance(x, y, $0.x, $0.y, aspect: aspect)) }
            .filter { $0.d <= $0.hold.r + slack }
            .min { $0.d < $1.d }?
            .hold
    }

    /// The nearest hold of a color (any color when nil) within `maxDistance`.
    public static func nearest(to x: Double, _ y: Double, color: HoldColor?, in holds: [PhotoHold],
                               aspect: Double, maxDistance: Double, excluding: Set<UUID> = []) -> PhotoHold? {
        holds
            .filter { !excluding.contains($0.id) && (color == nil || $0.color == nil || $0.color == color) }
            .map { (hold: $0, d: distance(x, y, $0.x, $0.y, aspect: aspect)) }
            .filter { $0.d <= maxDistance }
            .min { $0.d < $1.d }?
            .hold
    }

    public struct CarriedRoute: Hashable, Sendable {
        public let steps: [RouteStep]
        /// Some holds found no match: staff should look at this route.
        public let needsReview: Bool
    }

    /// A route from the old photo mapped onto the new photo's holds: every
    /// hold goes to the nearest unused hold of its color within reach. When a
    /// start hold finds no match, the route keeps only what matched and is
    /// flagged for review; when nothing usable is left, it is empty.
    public static func carryOver(_ route: [RouteHold], onto holds: [PhotoHold], aspect: Double,
                                 maxDistance: Double = 0.04) -> CarriedRoute {
        var used = Set<UUID>()
        var steps: [RouteStep] = []
        var missing = 0
        // Starts first, so they get the best matches.
        let order = route.sorted { ($0.role == .start ? 0 : 1, $0.y, $0.x) < ($1.role == .start ? 0 : 1, $1.y, $1.x) }
        for old in order {
            if let match = nearest(to: old.x, old.y, color: old.color, in: holds, aspect: aspect,
                                   maxDistance: maxDistance, excluding: used) {
                used.insert(match.id)
                steps.append(RouteStep(holdId: match.id, role: old.role))
            } else {
                missing += 1
            }
        }
        let starts = steps.filter { $0.role == .start }.count
        if starts == 0 {
            return CarriedRoute(steps: [], needsReview: !route.isEmpty)
        }
        return CarriedRoute(steps: steps, needsReview: missing > 0)
    }
}

/// How staff build a route by tapping holds: a tap on a hold not in the
/// route adds it as a hand hold, then each tap moves it on:
/// hand → start → top → out of the route. At most two starts and two tops;
/// a full role is skipped.
public enum RouteBuilding {
    public static func tapped(_ holdId: UUID, in route: [RouteStep]) -> [RouteStep] {
        var steps = route
        guard let index = steps.firstIndex(where: { $0.holdId == holdId }) else {
            steps.append(RouteStep(holdId: holdId, role: .hand))
            return steps
        }
        let others = steps.enumerated().filter { $0.offset != index }.map(\.element)
        let starts = others.filter { $0.role == .start }.count
        let tops = others.filter { $0.role == .top }.count
        switch steps[index].role {
        case .hand where starts < 2:
            steps[index].role = .start
        case .hand where tops < 2, .start where tops < 2:
            steps[index].role = .top
        default:
            steps.remove(at: index)
        }
        return steps
    }

    /// A route can be saved when it is empty or has one or two starts and at
    /// most two tops (the database checks the same).
    public static func isValid(_ route: [RouteStep]) -> Bool {
        let starts = route.filter { $0.role == .start }.count
        let tops = route.filter { $0.role == .top }.count
        return route.isEmpty || ((1...2).contains(starts) && tops <= 2)
    }
}
