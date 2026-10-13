import Foundation

// Gym visit detection (PLAN.md flow 5): the system reports entering and
// leaving a circle around a gym; this file turns those raw events into
// visits and decides when to remind about the session summary. No route or
// position is ever stored, only gym ids and entry/exit times.

/// Tuning of visit detection.
public enum VisitRules {
    /// Smaller circles fire late or not at all indoors.
    public static let minimumRadius: Double = 150
    /// Leaving is confirmed only after this long outside (indoor geofences are noisy).
    public static let exitDebounce: TimeInterval = 5 * 60
    /// Shorter stays (passing by, a coffee at the counter) are not visits.
    public static let minimumStay: TimeInterval = 20 * 60
    /// The system caps monitored conditions per app; leave headroom.
    public static let maximumMonitoredGyms = 15
    /// A reminder that could not be delivered in time is dropped after this.
    public static let reminderExpiry: TimeInterval = 6 * 3600
    /// Local visit history is trimmed to this age.
    public static let historyRetention: TimeInterval = 60 * 86_400
    public static let maximumHistoryCount = 200
}

/// A WGS-84 coordinate.
public struct GeoPoint: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres (haversine).
    public func distance(to other: GeoPoint) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLng = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * earthRadius * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// The circle monitored around one gym, kept locally so that events can be
/// handled when the app is launched in the background without a network.
public struct GymGeofence: Identifiable, Hashable, Codable, Sendable {
    /// The gym id.
    public let id: UUID
    public var name: String
    public var timezone: String
    public var center: GeoPoint
    public var radius: Double

    public init(id: UUID, name: String, timezone: String, center: GeoPoint, radius: Double) {
        self.id = id
        self.name = name
        self.timezone = timezone
        self.center = center
        self.radius = max(radius, VisitRules.minimumRadius)
    }

    /// Nil for a gym without coordinates.
    public init?(gym: Gym) {
        guard let latitude = gym.latitude, let longitude = gym.longitude else { return nil }
        self.init(
            id: gym.id,
            name: gym.name,
            timezone: gym.timezone,
            center: GeoPoint(latitude: latitude, longitude: longitude),
            radius: Double(gym.geofenceRadiusM)
        )
    }

    public var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }

    public func contains(_ point: GeoPoint) -> Bool {
        center.distance(to: point) <= radius
    }
}

public enum GeofencePlanner {
    /// The gyms worth monitoring: with coordinates, not muted, most recently
    /// visited first (then in the given order), at most `limit`.
    public static func select(
        _ geofences: [GymGeofence],
        muted: Set<UUID>,
        lastVisits: [UUID: Date],
        limit: Int = VisitRules.maximumMonitoredGyms
    ) -> [GymGeofence] {
        let candidates = geofences.enumerated().filter { !muted.contains($0.element.id) }
        let sorted = candidates.sorted { lhs, rhs in
            switch (lastVisits[lhs.element.id], lastVisits[rhs.element.id]) {
            case let (l?, r?) where l != r: l > r
            case (_?, nil): true
            case (nil, _?): false
            default: lhs.offset < rhs.offset
            }
        }
        return sorted.prefix(max(limit, 0)).map(\.element)
    }

    /// Overlapping circles: the gym whose centre is nearest to `point`.
    public static func nearest(to point: GeoPoint, among geofences: [GymGeofence]) -> GymGeofence? {
        geofences.min { lhs, rhs in
            let l = lhs.center.distance(to: point)
            let r = rhs.center.distance(to: point)
            return l != r ? l < r : lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

/// One stay at a gym. `exit` is nil while still inside.
public struct Visit: Hashable, Codable, Sendable, Identifiable {
    public var gymId: UUID
    public var entry: Date
    public var exit: Date?

    public init(gymId: UUID, entry: Date, exit: Date? = nil) {
        self.gymId = gymId
        self.entry = entry
        self.exit = exit
    }

    /// Stable across a debounced re-entry (the entry time is kept), so a
    /// pending reminder can be replaced or cancelled by this identifier.
    public var id: String { "visit-\(gymId.uuidString)-\(Int(entry.timeIntervalSince1970))" }

    public func duration(until now: Date) -> TimeInterval {
        (exit ?? now).timeIntervalSince(entry)
    }

    /// The climbing day (04:00 boundary, gym time) on which the visit began:
    /// an evening session that runs past midnight stays on its day.
    public func climbingDay(in timeZone: TimeZone) -> LocalDate {
        ClimbingDay.localDate(for: entry, in: timeZone)
    }
}

/// "Summarize your session" after leaving a gym.
public struct VisitReminder: Hashable, Sendable, Identifiable {
    public let visit: Visit
    public let fireDate: Date

    public var id: String { visit.id }
    public var gymId: UUID { visit.gymId }
    public var duration: TimeInterval { visit.duration(until: fireDate) }

    /// Too late to be useful (e.g. the event reached the app hours later).
    public func isExpired(now: Date) -> Bool {
        now.timeIntervalSince(fireDate) > VisitRules.reminderExpiry
    }
}

public enum VisitAction: Hashable, Sendable {
    /// Schedule (or replace) the reminder with this id.
    case schedule(VisitReminder)
    /// Withdraw a pending reminder: the climber came back in time.
    case cancel(id: String)
}

/// Turns raw enter/exit events into visits. A value type persisted as a
/// whole after every event; duplicate and out-of-place events are ignored,
/// so replaying the monitor's last known states on launch is safe.
public struct VisitTracker: Hashable, Codable, Sendable {
    /// Gyms whose circle currently contains the phone, with the entry time.
    public private(set) var presence: [UUID: Date] = [:]
    /// The visit in progress or awaiting the end of its exit debounce.
    public private(set) var current: Visit?
    /// Finished visits of at least `VisitRules.minimumStay`, oldest first.
    public private(set) var history: [Visit] = []

    public init() {}

    /// The phone entered the circle of `gymId`. `location` (if recent) and
    /// `geofences` resolve overlapping circles to the nearest centre.
    public mutating func enter(
        _ gymId: UUID,
        at date: Date,
        location: GeoPoint? = nil,
        geofences: [GymGeofence] = []
    ) -> [VisitAction] {
        settle(now: date)
        if presence[gymId] == nil { presence[gymId] = date }
        guard let chosen = attributedGym(location: location, geofences: geofences) else { return [] }

        if var visit = current {
            if visit.gymId == chosen {
                guard visit.exit != nil else { return [] } // already inside
                // Back within the debounce: the same visit goes on.
                visit.exit = nil
                current = visit
                return [.cancel(id: visit.id)]
            }
            if visit.exit == nil {
                // Overlapping circles, never left the area: re-attribute.
                visit.gymId = chosen
                current = visit
                return []
            }
            // Left the previous gym (its reminder stays scheduled).
            archive(visit)
        }
        current = Visit(gymId: chosen, entry: presence[chosen] ?? date)
        return []
    }

    /// The phone left the circle of `gymId`.
    public mutating func exit(
        _ gymId: UUID,
        at date: Date,
        location: GeoPoint? = nil,
        geofences: [GymGeofence] = []
    ) -> [VisitAction] {
        settle(now: date)
        guard presence.removeValue(forKey: gymId) != nil else { return [] }
        guard var visit = current, visit.gymId == gymId, visit.exit == nil else { return [] }

        if let other = attributedGym(location: location, geofences: geofences) {
            // Still inside an overlapping circle of another gym.
            visit.gymId = other
            current = visit
            return []
        }

        visit.exit = date
        current = visit
        guard visit.duration(until: date) >= VisitRules.minimumStay else { return [] }
        return [.schedule(VisitReminder(visit: visit, fireDate: date.addingTimeInterval(VisitRules.exitDebounce)))]
    }

    /// Moves a visit whose exit debounce has elapsed into the history.
    public mutating func settle(now: Date) {
        if let visit = current, let exit = visit.exit, now.timeIntervalSince(exit) >= VisitRules.exitDebounce {
            archive(visit)
            current = nil
        }
    }

    /// Stops tracking a gym (muted or no longer monitored) without a reminder.
    public mutating func forget(_ gymId: UUID) {
        presence[gymId] = nil
        if current?.gymId == gymId { current = nil }
    }

    public mutating func clearHistory() {
        history = []
    }

    /// The latest entry per gym, for choosing which gyms to monitor.
    public var lastVisits: [UUID: Date] {
        var result: [UUID: Date] = [:]
        for visit in history + [current].compactMap({ $0 }) {
            result[visit.gymId] = max(result[visit.gymId] ?? .distantPast, visit.entry)
        }
        return result
    }

    // MARK: Private

    private func attributedGym(location: GeoPoint?, geofences: [GymGeofence]) -> UUID? {
        let inside = presence.keys
        if inside.count <= 1 { return inside.first }
        let candidates = geofences.filter { presence[$0.id] != nil }
        if let location, let nearest = GeofencePlanner.nearest(to: location, among: candidates) {
            return nearest.id
        }
        // No fix: keep the current attribution, else the earliest entry.
        if let gymId = current?.gymId, presence[gymId] != nil { return gymId }
        return presence.min { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.uuidString < rhs.key.uuidString
        }?.key
    }

    private mutating func archive(_ visit: Visit) {
        guard let exit = visit.exit, visit.duration(until: exit) >= VisitRules.minimumStay else { return }
        history.removeAll { $0.id == visit.id }
        history.append(visit)
        history.sort { $0.entry < $1.entry }
        let cutoff = exit.addingTimeInterval(-VisitRules.historyRetention)
        history.removeAll { $0.entry < cutoff }
        if history.count > VisitRules.maximumHistoryCount {
            history.removeFirst(history.count - VisitRules.maximumHistoryCount)
        }
    }
}

/// Where the gym visit detection stands, from the user's settings and the
/// system permissions (mirrored here to keep this testable without iOS).
public enum VisitDetectionStatus: Hashable, Sendable {
    public enum LocationPermission: Hashable, Sendable {
        case notDetermined, denied, restricted, whenInUse, always
    }

    public enum NotificationPermission: Hashable, Sendable {
        case notDetermined, denied, granted
    }

    case off
    /// Step 1: location while using the app.
    case needsLocation
    /// Step 2: upgrade to "Always".
    case needsAlways
    /// "Always" was declined; only the Settings app can change it now.
    case alwaysDenied
    case locationDenied
    case reducedAccuracy
    case noGyms
    /// Visits are detected but reminders cannot be shown.
    case needsNotifications
    case notificationsDenied
    case active(gymCount: Int)

    public static func evaluate(
        isEnabled: Bool,
        location: LocationPermission,
        isPrecise: Bool,
        alwaysDeclined: Bool,
        notifications: NotificationPermission,
        monitoredGyms: Int
    ) -> VisitDetectionStatus {
        guard isEnabled else { return .off }
        switch location {
        case .notDetermined: return .needsLocation
        case .denied, .restricted: return .locationDenied
        case .whenInUse: return alwaysDeclined ? .alwaysDenied : .needsAlways
        case .always: break
        }
        guard isPrecise else { return .reducedAccuracy }
        guard monitoredGyms > 0 else { return .noGyms }
        switch notifications {
        case .notDetermined: return .needsNotifications
        case .denied: return .notificationsDenied
        case .granted: return .active(gymCount: monitoredGyms)
        }
    }

    /// Whether gyms should be monitored at all.
    public var canMonitor: Bool {
        switch self {
        case .needsNotifications, .notificationsDenied, .active, .noGyms: true
        default: false
        }
    }
}

public enum VisitDurationText {
    /// "45 min", "1 h", "1 h 30 min" — rounded to 5 minutes (geofences are
    /// not more precise than that).
    public static func polish(_ duration: TimeInterval) -> String {
        let minutes = max(5, Int((duration / 300).rounded()) * 5)
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
    }
}

/// Opens "Podsumuj sesję" for a gym and climbing day:
/// `wspinaczka://session?gym=<uuid>&day=yyyy-MM-dd`, also carried by the
/// visit reminder notification.
public struct SessionRoute: Hashable, Sendable, Identifiable {
    public let gymId: UUID
    public let day: LocalDate

    public init(gymId: UUID, day: LocalDate) {
        self.gymId = gymId
        self.day = day
    }

    public var id: String { "\(gymId.uuidString)/\(day)" }

    public init?(url: URL) {
        guard url.scheme == "wspinaczka", url.host == "session",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        self.init(gym: items.first { $0.name == "gym" }?.value, day: items.first { $0.name == "day" }?.value)
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "wspinaczka"
        components.host = "session"
        components.queryItems = [
            URLQueryItem(name: "gym", value: gymId.uuidString),
            URLQueryItem(name: "day", value: day.description),
        ]
        return components.url!
    }

    public init?(userInfo: [AnyHashable: Any]) {
        self.init(gym: userInfo["gym"] as? String, day: userInfo["day"] as? String)
    }

    public var userInfo: [String: String] {
        ["gym": gymId.uuidString, "day": day.description]
    }

    private init?(gym: String?, day: String?) {
        guard let gym, let gymId = UUID(uuidString: gym), let day, let date = LocalDate(day) else { return nil }
        self.init(gymId: gymId, day: date)
    }
}
