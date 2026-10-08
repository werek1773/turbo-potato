import BoulderKit
import SwiftUI

/// Profile → "Przypomnienie po wizycie": opt-in, permissions, per-gym switches
/// and the locally stored visits.
struct VisitSettingsView: View {
    @Environment(VisitMonitor.self) private var visits
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingSetup = false
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Przypominaj o podsumowaniu", isOn: Binding(
                    get: { visits.state.isEnabled },
                    set: { isOn in
                        visits.setEnabled(isOn)
                        if isOn, visits.status.needsSetup { isShowingSetup = true }
                    }
                ))
            } footer: {
                Text("Gdy wyjdziesz ze ścianki po ponad 20 minutach, telefon przypomni o podsumowaniu sesji. Stuknięcie otwiera podsumowanie tej ścianki i tego dnia.")
            }

            if visits.state.isEnabled {
                Section {
                    VisitStatusRow(status: visits.status)
                    if visits.status.needsSetup {
                        Button("Skonfiguruj uprawnienia", systemImage: "checklist") { isShowingSetup = true }
                    }
                } header: {
                    Text("Stan")
                } footer: {
                    if !visits.status.isWorking {
                        Text("Bez tych uprawnień nic się nie psuje — sesję podsumujesz ręcznie w zakładce Sesja.")
                    }
                }

                gymsSection
                historySection
            }

            Section("Prywatność") {
                Text(VisitPrivacy.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .canvasBackground()
        .navigationTitle("Przypomnienie po wizycie")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingSetup) { VisitSetupView() }
        .task { await visits.refreshPermissions() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await visits.refreshPermissions() } }
        }
    }

    private var gymsSection: some View {
        Section {
            ForEach(app.gyms) { gym in
                if gym.latitude != nil {
                    Toggle(gym.displayName, isOn: Binding(
                        get: { !visits.isMuted(gym.id) },
                        set: { visits.setMuted(gym.id, !$0) }
                    ))
                } else {
                    LabeledContent(gym.displayName, value: "brak lokalizacji")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Ścianki")
        } footer: {
            Text("Wyłącz ściankę, na której pracujesz, np. jako routesetter. Obserwowanych jest najwyżej \(VisitRules.maximumMonitoredGyms) ścianek — ostatnio odwiedzane mają pierwszeństwo.")
        }
    }

    @ViewBuilder
    private var historySection: some View {
        let recent = Array(visits.recentVisits.prefix(10))
        if !recent.isEmpty {
            Section {
                ForEach(recent) { visit in
                    Button {
                        if let route = visits.route(for: visit) { visits.open(route) }
                    } label: {
                        VisitRow(visit: visit, gym: visits.geofence(for: visit.gymId))
                    }
                    .buttonStyle(.plain)
                }
                Button("Usuń historię wizyt", role: .destructive) { isConfirmingClear = true }
                    .confirmationDialog("Usunąć zapisane wizyty z tego telefonu?", isPresented: $isConfirmingClear,
                                        titleVisibility: .visible) {
                        Button("Usuń", role: .destructive) { visits.clearHistory() }
                    }
            } header: {
                Text("Ostatnie wizyty")
            } footer: {
                Text("Stuknij wizytę, aby ją podsumować. Zapisane tylko na tym telefonie.")
            }
        }
    }
}

private struct VisitRow: View {
    let visit: Visit
    let gym: GymGeofence?

    var body: some View {
        let timeZone = gym?.timeZone ?? .current
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(gym?.name ?? "Ścianka").font(.headline)
                Text(times(in: timeZone)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(VisitDurationText.polish(visit.duration(until: visit.exit ?? .now)))
                .font(.subheadline.monospacedDigit())
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func times(in timeZone: TimeZone) -> String {
        var day = Date.FormatStyle(date: .abbreviated, time: .omitted)
        day.timeZone = timeZone
        var time = Date.FormatStyle(date: .omitted, time: .shortened)
        time.timeZone = timeZone
        let start = "\(visit.entry.formatted(day)), \(visit.entry.formatted(time))"
        guard let exit = visit.exit else { return start }
        return "\(start)–\(exit.formatted(time))"
    }
}

struct VisitStatusRow: View {
    let status: VisitDetectionStatus

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                if let detail = status.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: status.isWorking ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(status.isWorking ? Palette.moss : Palette.mustardText)
        }
    }
}

/// The explanation shown before any system prompt, then one step per permission.
struct VisitSetupView: View {
    @Environment(VisitMonitor.self) private var visits
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "location.circle")
                        .font(.system(size: 56))
                        .foregroundStyle(Palette.moss)
                        .frame(maxWidth: .infinity)

                    Text("Na ściance telefon zostaje w szafce. Gdy wyjdziesz, aplikacja przypomni o podsumowaniu sesji — wystarczą trzy zgody.")
                        .font(.body)

                    VisitSetupStep(
                        number: 1,
                        title: "Lokalizacja podczas używania",
                        explanation: "Pozwala zarejestrować okrąg wokół ścianki.",
                        isDone: visits.locationPermission == .whenInUse || visits.locationPermission == .always
                    ) {
                        switch visits.locationPermission {
                        case .notDetermined:
                            Button("Zezwól na lokalizację") { visits.requestLocationWhenInUse() }
                                .buttonStyle(.glassProminent)
                        case .denied, .restricted:
                            settingsButton("Lokalizacja jest wyłączona dla aplikacji.")
                        default:
                            EmptyView()
                        }
                    }

                    VisitSetupStep(
                        number: 2,
                        title: "Lokalizacja „Zawsze”",
                        explanation: "Wychodzisz ze ścianki, gdy aplikacja jest zamknięta. Tylko przy zgodzie „Zawsze” system może ją wtedy obudzić. Aplikacja nie śledzi Cię w tle: system informuje ją wyłącznie o wejściu do okręgu wokół ścianki i wyjściu z niego.",
                        isDone: visits.locationPermission == .always
                    ) {
                        if visits.locationPermission == .whenInUse {
                            if visits.state.hasAskedForAlways || visits.isAlwaysDeniedBySystem {
                                settingsButton("Wybierz „Zawsze” w Ustawieniach → Wspinaczka → Lokalizacja.")
                            } else {
                                Button("Zezwól „Zawsze”") { visits.requestLocationAlways() }
                                    .buttonStyle(.glassProminent)
                            }
                        }
                    }

                    if visits.locationPermission == .always, !visits.isPreciseLocation {
                        settingsButton("Włącz „Dokładna lokalizacja” — przybliżona nie wystarcza, by wykryć wizytę.")
                    }

                    VisitSetupStep(
                        number: 3,
                        title: "Powiadomienia",
                        explanation: "Jedno przypomnienie po wizycie trwającej ponad 20 minut.",
                        isDone: visits.notificationPermission == .granted
                    ) {
                        switch visits.notificationPermission {
                        case .notDetermined:
                            Button("Zezwól na powiadomienia") { Task { await visits.requestNotifications() } }
                                .buttonStyle(.glassProminent)
                        case .denied:
                            settingsButton("Powiadomienia są wyłączone dla aplikacji.")
                        case .granted:
                            EmptyView()
                        }
                    }

                    Text("Możesz pominąć dowolny krok — sesję zawsze podsumujesz ręcznie w zakładce Sesja.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .canvasBackground()
            .navigationTitle("Przypomnienie po wizycie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
            .task { await visits.refreshPermissions() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await visits.refreshPermissions() } }
            }
        }
    }

    private func settingsButton(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.footnote).foregroundStyle(.secondary)
            Button("Otwórz Ustawienia", systemImage: "gear") { visits.openSystemSettings() }
                .buttonStyle(.glass)
        }
    }
}

private struct VisitSetupStep<Action: View>: View {
    let number: Int
    let title: String
    let explanation: String
    let isDone: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(isDone ? Palette.moss : Palette.muted)
                .accessibilityLabel(isDone ? "Gotowe" : "Krok \(number)")
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(explanation).font(.subheadline).foregroundStyle(.secondary)
                if !isDone { action() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

enum VisitPrivacy {
    static let note = "Aplikacja nie zapisuje Twojego położenia ani trasy. System informuje ją tylko o wejściu do okręgu (min. 150 m) wokół wybranych ścianek i wyjściu z niego. Godziny wizyt zostają na tym telefonie, nie trafiają na serwer ani do ścianki. Wyłączenie przypomnień usuwa zapisane wizyty."
}

extension VisitDetectionStatus {
    var title: String {
        switch self {
        case .off: "Wyłączone"
        case .needsLocation: "Potrzebna zgoda na lokalizację"
        case .needsAlways: "Potrzebna zgoda „Zawsze”"
        case .alwaysDenied: "Brak zgody „Zawsze”"
        case .locationDenied: "Lokalizacja wyłączona"
        case .reducedAccuracy: "Przybliżona lokalizacja"
        case .noGyms: "Brak ścianek do obserwowania"
        case .needsNotifications: "Potrzebna zgoda na powiadomienia"
        case .notificationsDenied: "Powiadomienia wyłączone"
        case let .active(count): count == 1 ? "Działa — 1 ścianka" : "Działa — ścianki: \(count)"
        }
    }

    var detail: String? {
        switch self {
        case .alwaysDenied: "Zmienisz to w Ustawieniach → Wspinaczka → Lokalizacja."
        case .locationDenied: "Włącz lokalizację w Ustawieniach, aby wykrywać wizyty."
        case .reducedAccuracy: "Włącz „Dokładna lokalizacja” w Ustawieniach."
        case .noGyms: "Żadna włączona ścianka nie ma ustawionej lokalizacji."
        case .needsNotifications, .notificationsDenied: "Wizyty są wykrywane, ale bez przypomnień."
        default: nil
        }
    }

    var isWorking: Bool {
        if case .active = self { true } else { false }
    }

    /// Something the setup sheet can still help with.
    var needsSetup: Bool {
        switch self {
        case .needsLocation, .needsAlways, .alwaysDenied, .locationDenied, .reducedAccuracy,
             .needsNotifications, .notificationsDenied: true
        case .off, .noGyms, .active: false
        }
    }
}
