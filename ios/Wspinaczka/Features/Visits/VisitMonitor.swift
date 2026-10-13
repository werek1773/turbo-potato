import BoulderKit
import CoreLocation
import Foundation
import Observation
import UIKit
import UserNotifications

/// Detects gym visits with `CLMonitor` circles and reminds to summarize the
/// session after leaving (PLAN.md flow 5).
///
/// - Started from `WspinaczkaApp.init`, so a background launch for a
///   geofence event recreates the monitor and consumes its events at once.
/// - No `UIBackgroundModes: location`: the system relaunches the app for
///   monitor events when it has "Always" authorization and holds a
///   `CLServiceSession` requiring it.
/// - The exit debounce runs without background time: the reminder is
///   scheduled `exitDebounce` ahead and withdrawn if the phone comes back.
/// - Without "Always", with approximate location or no gyms, nothing is
///   monitored; "Podsumuj sesję" works by hand as before.
@MainActor
@Observable
final class VisitMonitor: NSObject {
    static let shared = VisitMonitor()

    private static let monitorName = "wspinaczka.gym-visits"

    private(set) var state: VisitState
    private(set) var locationPermission: VisitDetectionStatus.LocationPermission = .notDetermined
    private(set) var isPreciseLocation = true
    private(set) var notificationPermission: VisitDetectionStatus.NotificationPermission = .notDetermined
    /// Set by the service session when the user turned "Always" down.
    private(set) var isAlwaysDeniedBySystem = false
    /// Opened from a reminder or a `wspinaczka://session` link.
    var pendingSummary: SessionRoute?

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let notificationDelegate = VisitNotificationDelegate()
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var alwaysSession: CLServiceSession?
    @ObservationIgnored private var diagnosticsTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false

    private override init() {
        state = VisitStore.load()
        super.init()
    }

    // MARK: Status

    var status: VisitDetectionStatus {
        .evaluate(
            isEnabled: state.isEnabled,
            location: locationPermission,
            isPrecise: isPreciseLocation,
            alwaysDeclined: state.hasAskedForAlways || isAlwaysDeniedBySystem,
            notifications: notificationPermission,
            monitoredGyms: plannedGyms.count
        )
    }

    /// Gyms to monitor once permissions allow it.
    var plannedGyms: [GymGeofence] {
        GeofencePlanner.select(state.knownGyms, muted: state.mutedGymIds, lastVisits: state.tracker.lastVisits)
    }

    /// Finished visits, newest first.
    var recentVisits: [Visit] {
        state.tracker.history.reversed()
    }

    func geofence(for gymId: UUID) -> GymGeofence? {
        state.knownGyms.first { $0.id == gymId } ?? state.monitored.first { $0.id == gymId }
    }

    func route(for visit: Visit) -> SessionRoute? {
        guard let gym = geofence(for: visit.gymId) else { return nil }
        return SessionRoute(gymId: visit.gymId, day: visit.climbingDay(in: gym.timeZone))
    }

    // MARK: Lifecycle

    /// Call as early as possible on every launch, including background ones.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        UNUserNotificationCenter.current().delegate = notificationDelegate
        locationManager.delegate = self
        state.tracker.settle(now: .now)
        refreshLocationPermission()
        openMonitorIfNeeded()
        Task { await refreshNotificationPermission() }
    }

    /// The catalog loaded: remember the gyms' circles for background launches.
    func updateGyms(_ gyms: [Gym]) {
        let known = gyms.compactMap(GymGeofence.init(gym:))
        guard known != state.knownGyms else { return }
        state.knownGyms = known
        save()
        reconcile()
    }

    func refreshPermissions() async {
        refreshLocationPermission()
        await refreshNotificationPermission()
    }

    // MARK: Settings

    func setEnabled(_ isEnabled: Bool) {
        state.isEnabled = isEnabled
        if isEnabled {
            if locationPermission == .always { holdAlwaysSession() }
        } else {
            // Turning it off forgets the visits too.
            state.tracker = VisitTracker()
            state.lastEventDates = [:]
            releaseAlwaysSession()
            removeReminders { _ in true }
        }
        save()
        reconcile()
    }

    func isMuted(_ gymId: UUID) -> Bool {
        state.mutedGymIds.contains(gymId)
    }

    func setMuted(_ gymId: UUID, _ isMuted: Bool) {
        if isMuted {
            state.mutedGymIds.insert(gymId)
            state.tracker.forget(gymId)
            removeReminders { $0 == gymId }
        } else {
            state.mutedGymIds.remove(gymId)
        }
        save()
        reconcile()
    }

    func clearHistory() {
        state.tracker.clearHistory()
        save()
    }

    func open(_ route: SessionRoute) {
        pendingSummary = route
    }

    // MARK: Permissions

    /// Step 1: location while using the app.
    func requestLocationWhenInUse() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Step 2, after the explanation: upgrade to "Always". The service
    /// session requiring it is what lets the monitor work in the background.
    func requestLocationAlways() {
        state.hasAskedForAlways = true
        save()
        holdAlwaysSession()
        locationManager.requestAlwaysAuthorization()
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshNotificationPermission()
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func refreshLocationPermission() {
        locationPermission = switch locationManager.authorizationStatus {
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whenInUse
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
        isPreciseLocation = locationManager.accuracyAuthorization == .fullAccuracy
        if locationPermission == .always {
            isAlwaysDeniedBySystem = false
            if state.isEnabled { holdAlwaysSession() }
        }
        reconcile()
    }

    private func refreshNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermission = switch settings.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .granted
        }
    }

    private func holdAlwaysSession() {
        guard alwaysSession == nil else { return }
        let session = CLServiceSession(authorization: .always)
        alwaysSession = session
        diagnosticsTask = Task { [weak self] in
            do {
                for try await diagnostic in session.diagnostics {
                    self?.isAlwaysDeniedBySystem = diagnostic.alwaysAuthorizationDenied
                }
            } catch {}
        }
    }

    private func releaseAlwaysSession() {
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        alwaysSession?.invalidate()
        alwaysSession = nil
    }

    // MARK: Monitor

    /// Registers exactly the planned gyms when monitoring is possible, none otherwise.
    private func reconcile() {
        let desired = status.canMonitor ? plannedGyms : []
        guard Set(desired) != Set(state.monitored) else { return }
        for gym in state.monitored where !desired.contains(where: { $0.id == gym.id }) {
            state.tracker.forget(gym.id)
            state.lastEventDates[gym.id] = nil
        }
        state.monitored = desired
        save()
        openMonitorIfNeeded()
        if let monitor {
            Task { await syncConditions(of: monitor) }
        }
    }

    private func openMonitorIfNeeded() {
        guard monitorTask == nil, state.isEnabled || !state.monitored.isEmpty else { return }
        monitorTask = Task {
            let monitor = await CLMonitor(Self.monitorName)
            self.monitor = monitor
            Task {
                await self.syncConditions(of: monitor)
                await self.replayLastEvents(of: monitor)
            }
            do {
                for try await event in await monitor.events {
                    self.handle(event.state, gymIdentifier: event.identifier, date: event.date)
                }
            } catch {}
            self.monitor = nil
            self.monitorTask = nil
        }
    }

    private func syncConditions(of monitor: CLMonitor) async {
        let wanted = Dictionary(uniqueKeysWithValues: state.monitored.map { ($0.id.uuidString, $0) })
        for identifier in await monitor.identifiers where wanted[identifier] == nil {
            await monitor.remove(identifier)
        }
        for (identifier, gym) in wanted {
            if let record = await monitor.record(for: identifier),
               let condition = record.condition as? CLMonitor.CircularGeographicCondition,
               condition.radius == gym.radius,
               abs(condition.center.latitude - gym.center.latitude) < 1e-7,
               abs(condition.center.longitude - gym.center.longitude) < 1e-7 {
                continue
            }
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: gym.center.latitude, longitude: gym.center.longitude),
                radius: gym.radius
            )
            await monitor.add(condition, identifier: identifier, assuming: .unsatisfied)
        }
    }

    /// Catches up on states the stream may not repeat after a relaunch.
    private func replayLastEvents(of monitor: CLMonitor) async {
        for gym in state.monitored {
            guard let event = await monitor.record(for: gym.id.uuidString)?.lastEvent else { continue }
            handle(event.state, gymIdentifier: event.identifier, date: event.date)
        }
    }

    private func handle(_ monitoringState: CLMonitor.Event.State, gymIdentifier: String, date: Date) {
        guard let gymId = UUID(uuidString: gymIdentifier),
              state.monitored.contains(where: { $0.id == gymId })
        else { return }
        if let last = state.lastEventDates[gymId], date < last { return }

        let location = recentLocation()
        let actions: [VisitAction]
        switch monitoringState {
        case .satisfied:
            actions = state.tracker.enter(gymId, at: date, location: location, geofences: state.monitored)
        case .unsatisfied:
            actions = state.tracker.exit(gymId, at: date, location: location, geofences: state.monitored)
        default:
            return
        }
        state.lastEventDates[gymId] = date
        save()
        perform(actions)
    }

    /// The system's last fix, only to pick the nearest of overlapping gyms.
    /// Never stored.
    private func recentLocation() -> GeoPoint? {
        guard let location = locationManager.location,
              location.timestamp.timeIntervalSinceNow > -600,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy < 500
        else { return nil }
        return GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    // MARK: Reminders

    private func perform(_ actions: [VisitAction]) {
        let center = UNUserNotificationCenter.current()
        for action in actions {
            switch action {
            case let .schedule(reminder):
                schedule(reminder)
            case let .cancel(id):
                center.removePendingNotificationRequests(withIdentifiers: [id])
            }
        }
    }

    private func schedule(_ reminder: VisitReminder) {
        guard !isMuted(reminder.gymId), !reminder.isExpired(now: .now),
              let gym = geofence(for: reminder.gymId)
        else { return }
        let route = SessionRoute(gymId: gym.id, day: reminder.visit.climbingDay(in: gym.timeZone))

        let content = UNMutableNotificationContent()
        content.title = gym.name
        content.body = "Twoja wizyta: \(VisitDurationText.polish(reminder.duration)). Podsumuj sesję, póki wszystko pamiętasz."
        content.sound = .default
        content.threadIdentifier = "gym-visits"
        content.userInfo = route.userInfo
        let delay = max(1, reminder.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func removeReminders(where matches: @escaping @Sendable (UUID) -> Bool) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.compactMap { request in
                SessionRoute(userInfo: request.content.userInfo).flatMap { matches($0.gymId) ? request.identifier : nil }
            }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func save() {
        VisitStore.save(state)
    }
}

extension VisitMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refreshLocationPermission() }
    }
}

/// Shows reminders in the foreground too and routes a tap to the summary.
final class VisitNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let route = SessionRoute(userInfo: response.notification.request.content.userInfo) {
            Task { @MainActor in VisitMonitor.shared.open(route) }
        }
        completionHandler()
    }
}
