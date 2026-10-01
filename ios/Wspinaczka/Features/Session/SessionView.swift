import BoulderKit
import SwiftUI

/// "Podsumuj sesję": after leaving the gym, tap the pins of what you climbed.
struct SessionView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedGymId: UUID?

    private var gym: Gym? {
        app.gyms.first { $0.id == selectedGymId } ?? app.gyms.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let gym {
                    SessionDayView(gym: gym)
                        .id(gym.id)
                } else {
                    ContentUnavailableView(
                        "Brak ścianki",
                        systemImage: "checklist",
                        description: Text("Gdy Twoja ścianka będzie dostępna, tutaj podsumujesz sesję.")
                    )
                }
            }
            .canvasBackground()
            .navigationTitle("Sesja")
            .toolbar {
                if app.gyms.count > 1 {
                    Menu {
                        Picker("Ścianka", selection: Binding(
                            get: { gym?.id },
                            set: { selectedGymId = $0 }
                        )) {
                            ForEach(app.gyms) { gym in
                                Text(gym.displayName).tag(Optional(gym.id))
                            }
                        }
                    } label: {
                        Label("Ścianka", systemImage: "mountain.2")
                    }
                }
            }
        }
    }
}

struct SessionDayView: View {
    @Environment(AppModel.self) private var app
    @State private var log: SessionLog
    @State private var detail: ActiveProblem?

    init(gym: Gym) {
        let catalog = GymCatalog(gym: gym, backend: .shared)
        _log = State(initialValue: SessionLog(catalog: catalog, day: catalog.today))
    }

    private var catalog: GymCatalog { log.catalog }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                DayHeader(log: log)

                if !catalog.coverage.isEmpty {
                    GradeFilterBar(catalog: catalog)
                }

                Text("Dotknij pinezki: Top → Flash → Projekt → nic. Przytrzymaj, aby dodać szczegóły.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(catalog.areas) { area in
                    let sectors = area.sectors.filter { catalog.photo(of: $0) != nil }
                    if !sectors.isEmpty {
                        if let name = area.name {
                            Text(name).font(.title2.bold()).padding(.top, 8)
                        }
                        ForEach(sectors) { sector in
                            SessionSectorCard(log: log, sector: sector) { problem in
                                detail = problem
                            }
                        }
                    }
                }

                if catalog.sectors.allSatisfy({ catalog.photo(of: $0) == nil }) && !catalog.isLoading {
                    ContentUnavailableView(
                        "Brak problemów",
                        systemImage: "mappin.slash",
                        description: Text("Routesetterzy jeszcze nie dodali problemów na zdjęciach sektorów.")
                    )
                }

                if !log.dayAscents.isEmpty {
                    LoggedList(log: log) { detail = $0 }
                }

                WellbeingSection(log: log)
            }
            .padding()
        }
        .sheet(item: $detail) { problem in
            AscentDetailSheet(log: log, problem: problem)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        do { try await log.load() } catch { app.report(error) }
    }
}

/// Day picker and the day's tally.
private struct DayHeader: View {
    @Bindable var log: SessionLog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                "Dzień sesji",
                selection: Binding(
                    get: { log.day.date(in: log.catalog.gym.timeZone) },
                    set: { log.day = LocalDate($0, in: log.catalog.gym.timeZone) }
                ),
                in: ...log.today.date(in: log.catalog.gym.timeZone),
                displayedComponents: .date
            )
            .font(.headline)

            let summary = log.summary
            HStack(spacing: 12) {
                Tally(result: .flash, count: summary.flashes)
                Tally(result: .top, count: summary.tops)
                Tally(result: .project, count: summary.projects)
                Spacer()
                if let hardest = summary.hardestTop {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("najtrudniejszy").font(.caption2).foregroundStyle(.secondary)
                        Text(hardest.label).font(.title2.bold())
                    }
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct Tally: View {
    let result: AscentResult
    let count: Int

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: result.symbol)
                .foregroundStyle(result.tint)
            Text("\(count)").font(.title3.bold().monospacedDigit())
            Text(result.polishName).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 52)
    }
}

/// A sector photo whose pins toggle the day's result.
private struct SessionSectorCard: View {
    let log: SessionLog
    let sector: Sector
    let onDetails: (ActiveProblem) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        let catalog = log.catalog
        let problems = catalog.problems(in: sector)
        let labels = catalog.gradesById.mapValues(\.label)
        let highlighted = catalog.visibleProblemIds

        VStack(alignment: .leading, spacing: 8) {
            Text(sector.name).font(.title3.bold())
            if let photo = catalog.photo(of: sector) {
                AsyncImage(url: catalog.backend.photoURL(for: photo)) { phase in
                    if case let .success(image) = phase {
                        image.resizable()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .aspectRatio(photo.aspectRatio, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        ForEach(problems) { problem in
                            ProblemPin(
                                color: problem.holdColor,
                                label: labels[problem.gradeId],
                                isHighlighted: highlighted.contains(problem.id),
                                sessionResult: log.results[problem.id]?.result
                            )
                            .opacity(log.saving.contains(problem.id) ? 0.6 : 1)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task {
                                    do { try await log.cycle(problem) } catch { app.report(error) }
                                }
                            }
                            .onLongPressGesture { onDetails(problem) }
                            .sensoryFeedback(.selection, trigger: log.results[problem.id]?.result)
                            .position(x: problem.pinX * proxy.size.width, y: problem.pinY * proxy.size.height)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

/// What I logged today, with a way into the details.
private struct LoggedList: View {
    let log: SessionLog
    let onSelect: (ActiveProblem) -> Void

    var body: some View {
        let catalog = log.catalog
        let grades = catalog.gradesById
        let logged = catalog.problems.filter { log.results[$0.id] != nil }

        VStack(alignment: .leading, spacing: 10) {
            Text("Twoja sesja").font(.title2.bold())
            ForEach(logged) { problem in
                if let ascent = log.results[problem.id] {
                    Button { onSelect(problem) } label: {
                        HStack(spacing: 12) {
                            ProblemPin(color: problem.holdColor, label: grades[problem.gradeId]?.label,
                                       sessionResult: ascent.result)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ascent.result.polishName).font(.headline)
                                Text(details(ascent))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func details(_ ascent: Ascent) -> String {
        var parts: [String] = []
        if let attempts = ascent.attempts { parts.append("próby: \(attempts.polishName)") }
        if let perceived = ascent.perceivedGrade { parts.append(perceived.polishName.lowercased()) }
        if !ascent.limiters.isEmpty { parts.append(ascent.limiters.map(\.polishName).joined(separator: ", ")) }
        return parts.isEmpty ? "Dotknij, aby dodać szczegóły" : parts.joined(separator: " · ")
    }
}
