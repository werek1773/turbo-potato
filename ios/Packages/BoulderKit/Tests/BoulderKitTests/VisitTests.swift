import Foundation
import Testing
@testable import BoulderKit

@Suite("Gym visits")
struct VisitTests {
    let volt = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let other = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    let warsaw = TimeZone(identifier: "Europe/Warsaw")!

    func instant(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    func minutes(_ value: Double, after date: Date) -> Date {
        date.addingTimeInterval(value * 60)
    }

    // MARK: Stay and debounce

    @Test func longStayIsRemindedAfterTheDebounce() throws {
        var tracker = VisitTracker()
        let entry = instant("2026-10-08T16:00:00Z")
        #expect(tracker.enter(volt, at: entry).isEmpty)
        let exit = minutes(90, after: entry)
        let actions = tracker.exit(volt, at: exit)

        let reminder = try #require(actions.first.flatMap { action -> VisitReminder? in
            if case let .schedule(reminder) = action { reminder } else { nil }
        })
        #expect(actions.count == 1)
        #expect(reminder.gymId == volt)
        #expect(reminder.fireDate == minutes(5, after: exit))
        #expect(reminder.visit.duration(until: .distantFuture) == 90 * 60)
        #expect(VisitDurationText.polish(reminder.visit.duration(until: exit)) == "1 h 30 min")
    }

    @Test func shortStayIsNotReminded() {
        var tracker = VisitTracker()
        let entry = instant("2026-10-08T16:00:00Z")
        _ = tracker.enter(volt, at: entry)
        #expect(tracker.exit(volt, at: minutes(19, after: entry)).isEmpty)
        tracker.settle(now: minutes(60, after: entry))
        #expect(tracker.current == nil)
        #expect(tracker.history.isEmpty)
    }

    @Test func reentryWithinTheDebounceContinuesTheVisit() throws {
        var tracker = VisitTracker()
        let entry = instant("2026-10-08T16:00:00Z")
        _ = tracker.enter(volt, at: entry)
        let firstExit = tracker.exit(volt, at: minutes(40, after: entry))
        guard case let .schedule(first)? = firstExit.first else {
            Issue.record("expected a reminder")
            return
        }

        // Back after 3 minutes (a noisy exit near the wall): withdraw it.
        #expect(tracker.enter(volt, at: minutes(43, after: entry)) == [.cancel(id: first.id)])
        #expect(tracker.current?.exit == nil)

        let actions = tracker.exit(volt, at: minutes(100, after: entry))
        guard case let .schedule(second)? = actions.first else {
            Issue.record("expected a reminder")
            return
        }
        #expect(second.id == first.id)
        #expect(second.visit.entry == entry)
        #expect(second.visit.duration(until: .now) == 100 * 60)
    }

    @Test func shortStaysAddUpAcrossANoisyExit() {
        var tracker = VisitTracker()
        let entry = instant("2026-10-08T16:00:00Z")
        _ = tracker.enter(volt, at: entry)
        #expect(tracker.exit(volt, at: minutes(10, after: entry)).isEmpty)
        _ = tracker.enter(volt, at: minutes(12, after: entry))
        #expect(tracker.exit(volt, at: minutes(30, after: entry)).count == 1)
    }

    @Test func returnAfterTheDebounceStartsANewVisit() {
        var tracker = VisitTracker()
        let entry = instant("2026-10-08T16:00:00Z")
        _ = tracker.enter(volt, at: entry)
        _ = tracker.exit(volt, at: minutes(60, after: entry))
        #expect(tracker.enter(volt, at: minutes(70, after: entry)).isEmpty)
        #expect(tracker.current?.entry == minutes(70, after: entry))
        #expect(tracker.history.map(\.entry) == [entry])
        #expect(tracker.lastVisits[volt] == minutes(70, after: entry))
    }

    @Test func duplicateAndStrayEventsAreIgnored() {
        var tracker = VisitTracker()
        let entry = instant("2026-10-08T16:00:00Z")
        #expect(tracker.exit(volt, at: entry).isEmpty) // never entered
        _ = tracker.enter(volt, at: entry)
        #expect(tracker.enter(volt, at: minutes(30, after: entry)).isEmpty)
        #expect(tracker.current?.entry == entry)
        #expect(tracker.exit(volt, at: minutes(60, after: entry)).count == 1)
        #expect(tracker.exit(volt, at: minutes(61, after: entry)).isEmpty)
    }

    @Test func forgettingAGymDropsItsVisit() {
        var tracker = VisitTracker()
        let entry = instant("2026-10-08T16:00:00Z")
        _ = tracker.enter(volt, at: entry)
        tracker.forget(volt)
        #expect(tracker.current == nil)
        #expect(tracker.exit(volt, at: minutes(60, after: entry)).isEmpty)
    }

    @Test func trackerRoundTripsThroughJSON() throws {
        var tracker = VisitTracker()
        let entry = instant("2026-10-08T16:00:00Z")
        _ = tracker.enter(volt, at: entry)
        _ = tracker.exit(volt, at: minutes(60, after: entry))
        tracker.settle(now: minutes(70, after: entry))
        _ = tracker.enter(volt, at: minutes(24 * 60, after: entry))
        let decoded = try JSONDecoder().decode(VisitTracker.self, from: JSONEncoder().encode(tracker))
        #expect(decoded == tracker)
    }

    // MARK: Overlapping circles

    var fences: [GymGeofence] {
        [
            GymGeofence(id: volt, name: "Volt", timezone: "Europe/Warsaw",
                        center: GeoPoint(latitude: 51.7600, longitude: 19.4600), radius: 150),
            GymGeofence(id: other, name: "Obok", timezone: "Europe/Warsaw",
                        center: GeoPoint(latitude: 51.7620, longitude: 19.4600), radius: 200),
        ]
    }

    @Test func overlappingCirclesGoToTheNearestCentre() {
        var tracker = VisitTracker()
        let entry = instant("2026-10-08T16:00:00Z")
        let nearVolt = GeoPoint(latitude: 51.7605, longitude: 19.4600)
        _ = tracker.enter(other, at: entry, location: nearVolt, geofences: fences)
        #expect(tracker.current?.gymId == other)
        _ = tracker.enter(volt, at: minutes(1, after: entry), location: nearVolt, geofences: fences)
        #expect(tracker.current?.gymId == volt)
        #expect(tracker.current?.entry == entry)

        // Leaving the larger circle only: still at Volt, no reminder.
        #expect(tracker.exit(other, at: minutes(50, after: entry), location: nearVolt, geofences: fences).isEmpty)
        let actions = tracker.exit(volt, at: minutes(60, after: entry), geofences: fences)
        guard case let .schedule(reminder)? = actions.first else {
            Issue.record("expected a reminder")
            return
        }
        #expect(reminder.gymId == volt)
    }

    @Test func withoutALocationTheFirstGymKeepsTheVisit() {
        var tracker = VisitTracker()
        let entry = instant("2026-10-08T16:00:00Z")
        _ = tracker.enter(volt, at: entry, geofences: fences)
        _ = tracker.enter(other, at: minutes(2, after: entry), geofences: fences)
        #expect(tracker.current?.gymId == volt)
        // Leaving Volt's circle while still inside the other one re-attributes.
        #expect(tracker.exit(volt, at: minutes(30, after: entry), geofences: fences).isEmpty)
        #expect(tracker.current?.gymId == other)
        #expect(tracker.exit(other, at: minutes(31, after: entry), geofences: fences).count == 1)
    }

    @Test func nearestCentreAndContainment() {
        let point = GeoPoint(latitude: 51.7615, longitude: 19.4600)
        #expect(GeofencePlanner.nearest(to: point, among: fences)?.id == other)
        #expect(fences[1].contains(point))
        #expect(!fences[0].contains(point))
        // ~222 m between the centres.
        #expect(abs(fences[0].center.distance(to: fences[1].center) - 222.4) < 1)
    }

    // MARK: Choosing gyms

    @Test func selectionPrefersRecentVisitsSkipsMutedAndCaps() {
        let ids = (0..<20).map { _ in UUID() }
        let all = ids.map {
            GymGeofence(id: $0, name: "x", timezone: "Europe/Warsaw",
                        center: GeoPoint(latitude: 51, longitude: 19), radius: 150)
        }
        let selected = GeofencePlanner.select(
            all,
            muted: [ids[0]],
            lastVisits: [ids[19]: .now, ids[18]: .now.addingTimeInterval(-3600), ids[0]: .now]
        )
        #expect(selected.count == VisitRules.maximumMonitoredGyms)
        #expect(selected.map(\.id).prefix(3) == [ids[19], ids[18], ids[1]])
        #expect(!selected.map(\.id).contains(ids[0]))
    }

    @Test func geofenceRadiusIsAtLeast150Metres() {
        let gym = Gym(id: volt, slug: "volt", name: "Volt", city: "Łódź", address: nil,
                      timezone: "Europe/Warsaw", latitude: 51.76, longitude: 19.46,
                      geofenceRadiusM: 100, publishedAt: nil, floorPlan: nil)
        #expect(GymGeofence(gym: gym)?.radius == 150)
        var noCoordinates = gym
        noCoordinates.latitude = nil
        noCoordinates.longitude = nil
        #expect(GymGeofence(gym: noCoordinates) == nil)
    }

    // MARK: Climbing day of a visit

    @Test func lateVisitBelongsToTheDayItStarted() {
        // 22:30 to 00:40 local (CEST): still 8 October.
        let visit = Visit(gymId: volt, entry: instant("2026-10-08T20:30:00Z"), exit: instant("2026-10-08T22:40:00Z"))
        #expect(visit.climbingDay(in: warsaw) == LocalDate("2026-10-08"))
    }

    @Test func earlyMorningVisitBelongsToThatDay() {
        // 06:30 local.
        let visit = Visit(gymId: volt, entry: instant("2026-10-09T04:30:00Z"))
        #expect(visit.climbingDay(in: warsaw) == LocalDate("2026-10-09"))
    }

    // MARK: Reminder, status, text, route

    @Test func staleRemindersExpire() {
        let exit = instant("2026-10-08T18:00:00Z")
        let reminder = VisitReminder(visit: Visit(gymId: volt, entry: minutes(-60, after: exit), exit: exit),
                                     fireDate: minutes(5, after: exit))
        #expect(!reminder.isExpired(now: minutes(60, after: exit)))
        #expect(reminder.isExpired(now: minutes(7 * 60, after: exit)))
    }

    @Test func durationText() {
        #expect(VisitDurationText.polish(21 * 60) == "20 min")
        #expect(VisitDurationText.polish(58 * 60) == "1 h")
        #expect(VisitDurationText.polish(92 * 60) == "1 h 30 min")
        #expect(VisitDurationText.polish(135 * 60) == "2 h 15 min")
    }

    @Test func statusWalksThroughTheSteps() {
        func status(
            _ location: VisitDetectionStatus.LocationPermission,
            precise: Bool = true,
            declined: Bool = false,
            notifications: VisitDetectionStatus.NotificationPermission = .granted,
            gyms: Int = 1,
            enabled: Bool = true
        ) -> VisitDetectionStatus {
            .evaluate(isEnabled: enabled, location: location, isPrecise: precise, alwaysDeclined: declined,
                      notifications: notifications, monitoredGyms: gyms)
        }
        #expect(status(.always, enabled: false) == .off)
        #expect(status(.notDetermined) == .needsLocation)
        #expect(status(.whenInUse) == .needsAlways)
        #expect(status(.whenInUse, declined: true) == .alwaysDenied)
        #expect(status(.denied) == .locationDenied)
        #expect(status(.always, precise: false) == .reducedAccuracy)
        #expect(status(.always, gyms: 0) == .noGyms)
        #expect(status(.always, notifications: .notDetermined) == .needsNotifications)
        #expect(status(.always, notifications: .denied) == .notificationsDenied)
        #expect(status(.always) == .active(gymCount: 1))
        #expect(status(.always, notifications: .denied).canMonitor)
        #expect(!status(.always, precise: false).canMonitor)
        #expect(!status(.whenInUse).canMonitor)
    }

    @Test func sessionRouteRoundTrips() throws {
        let route = SessionRoute(gymId: volt, day: LocalDate("2026-10-08")!)
        #expect(route.url.absoluteString == "wspinaczka://session?gym=\(volt.uuidString)&day=2026-10-08")
        #expect(SessionRoute(url: route.url) == route)
        #expect(SessionRoute(userInfo: route.userInfo) == route)
        #expect(SessionRoute(url: URL(string: "wspinaczka://invite?code=ABC")!) == nil)
        #expect(SessionRoute(url: URL(string: "wspinaczka://session?gym=nope&day=2026-10-08")!) == nil)
    }
}
