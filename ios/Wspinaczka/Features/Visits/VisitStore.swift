import BoulderKit
import Foundation

/// Everything visit detection keeps on this phone (never sent anywhere):
/// settings, the gyms' circles and entry/exit times. No positions or routes.
struct VisitState: Codable, Equatable {
    var isEnabled = false
    /// Gyms without reminders (e.g. where you work as a routesetter).
    var mutedGymIds: Set<UUID> = []
    /// Every gym with coordinates from the last catalog load.
    var knownGyms: [GymGeofence] = []
    /// Gyms whose circles are registered with the system monitor.
    var monitored: [GymGeofence] = []
    var tracker = VisitTracker()
    /// The latest handled monitor event per gym, so stale replays are skipped.
    var lastEventDates: [UUID: Date] = [:]
    /// iOS shows the "Always" prompt only once; afterwards only Settings can change it.
    var hasAskedForAlways = false
}

enum VisitStore {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "gym-visits.json")
    }

    static func load() -> VisitState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(VisitState.self, from: data)
        else { return VisitState() }
        return state
    }

    /// Readable after the first unlock: background launches for a geofence
    /// event usually happen with the phone locked.
    static func save(_ state: VisitState) {
        do {
            try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            assertionFailure("Saving visits failed: \(error)")
        }
    }
}
