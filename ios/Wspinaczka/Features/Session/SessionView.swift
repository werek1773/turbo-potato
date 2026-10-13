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
                    ChalkEmptyState(
                        title: "Brak ścianek",
                        message: "Gdy Twoja ścianka zostanie opublikowana, tutaj podsumujesz sesję.",
                        refresh: { await app.refresh() }
                    )
                }
            }
            .canvasBackground()
            .navigationTitle("Sesja")
            .navigationBarTitleDisplayMode(.inline)
            // The header names the day and the gym; the bar keeps only actions.
            .toolbar(removing: .title)
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
    @State private var log: SessionLog
    @State private var detail: ActiveProblem?
    @State private var isShowingRecap = false
    @State private var sectorId: UUID?

    /// `day` defaults to today (e.g. a detected visit opens its own day).
    init(gym: Gym, day: LocalDate? = nil) {
        let catalog = GymCatalog(gym: gym, backend: .shared)
        _log = State(initialValue: SessionLog(catalog: catalog, day: day ?? catalog.today))
    }

    private var catalog: GymCatalog { log.catalog }

    /// Walls with a photo, in walking order: the pages of the pager.
    private var sectors: [Sector] {
        catalog.areas.flatMap(\.sectors).filter { catalog.photo(of: $0) != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SessionHeader(log: log)
                DayStrip(log: log)
                TallyCard(log: log)
                SyncStatusView(log: log)

                if sectors.isEmpty {
                    if !catalog.isLoading {
                        VStack(spacing: 8) {
                            DrawingView(drawing: .chalk)
                                .frame(height: 120)
                            Text("Brak problemów")
                                .font(.display(.title3))
                            Text("Routesetterzy jeszcze nie dodali problemów na zdjęciach sektorów.")
                                .foregroundStyle(Palette.muted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    SectorPager(log: log, sectors: sectors, selection: $sectorId) { detail = $0 }
                }

                if !log.dayAscents.isEmpty {
                    LoggedList(log: log) { detail = $0 }
                }

                WellbeingSection(log: log)

                if !log.dayAscents.isEmpty {
                    Button("Zakończ sesję") { isShowingRecap = true }
                        .buttonStyle(.pill)
                }
            }
            .padding()
        }
        .canvasBackground()
        .sheet(isPresented: $isShowingRecap) {
            SessionRecapView(log: log)
        }
        .sheet(item: $detail) { problem in
            AscentDetailSheet(log: log, problem: problem)
        }
        .task { await log.load() }
        .refreshable {
            log.outbox.flushNow()
            await log.load()
        }
        .onChange(of: log.outbox.drainCount) { _, _ in
            Task { await log.reconcile() }
        }
    }
}

// MARK: - Header

/// "Dzisiaj" and one sentence: the gym and how much is logged, like the
/// header of the gym screen.
private struct SessionHeader: View {
    let log: SessionLog

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SessionDayText.title(log.day, today: log.today, in: log.catalog.gym.timeZone))
                .font(.display(.largeTitle))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(sentence)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sentence: String {
        let gym = log.catalog.gym.name
        let logged = log.summary.logged
        if logged == 0 {
            return "\(gym). Dotknij pinezek problemów z tej sesji."
        }
        return "\(gym). Zapisane: \(Counted.problems(logged))."
    }
}

enum SessionDayText {
    /// "Dzisiaj", "Wczoraj", "Wtorek, 6 października".
    static func title(_ day: LocalDate, today: LocalDate, in timeZone: TimeZone) -> String {
        switch day.days(until: today) {
        case 0: return "Dzisiaj"
        case 1: return "Wczoraj"
        default:
            var style = Date.FormatStyle().weekday(.wide).day().month(.wide)
            style.timeZone = timeZone
            style.locale = .app
            let text = day.date(in: timeZone).formatted(style)
            return text.prefix(1).uppercased() + text.dropFirst()
        }
    }

    /// Short Polish weekday names, Sunday first (Calendar's order).
    static let weekdays = ["nd", "pn", "wt", "śr", "cz", "pt", "sb"]

    static func weekday(_ day: LocalDate) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let utc = TimeZone(identifier: "UTC")!
        return weekdays[calendar.component(.weekday, from: day.date(in: utc)) - 1]
    }
}

// MARK: - Days

/// The last seven days: the chosen one circled in pen, a dot under days
/// with something logged; older days through the calendar.
private struct DayStrip: View {
    @Bindable var log: SessionLog
    @State private var isPickingDate = false

    private var days: [LocalDate] { (0..<7).reversed().map { log.today.adding(days: -$0) } }

    private var loggedDays: Set<LocalDate> { Set(log.catalog.myAscents.map(\.localDate)) }

    var body: some View {
        let logged = loggedDays
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isOn = day == log.day
                Button {
                    log.day = day
                } label: {
                    VStack(spacing: 2) {
                        Text(SessionDayText.weekday(day))
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                        Text("\(day.day)")
                            .font(.display(.body).monospacedDigit())
                            .foregroundStyle(isOn ? Palette.mossDark : Palette.ink)
                            .frame(width: 36, height: 36)
                            .background {
                                if isOn {
                                    PenCircle()
                                        .frame(width: 44, height: 44)
                                        .id(day)
                                }
                            }
                        Circle()
                            .fill(logged.contains(day) ? Palette.moss : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SessionDayText.title(day, today: log.today, in: log.catalog.gym.timeZone)
                                    + (logged.contains(day) ? ", sesja zapisana" : ""))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
            Button {
                isPickingDate = true
            } label: {
                Image(systemName: "calendar")
                    .font(.body.weight(.medium))
                    .foregroundStyle(days.contains(log.day) ? Palette.muted : Palette.mossDark)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wcześniejszy dzień")
        }
        .sensoryFeedback(.selection, trigger: log.day)
        .sheet(isPresented: $isPickingDate) {
            EarlierDaySheet(log: log)
                .presentationDetents([.medium])
        }
    }
}

private struct EarlierDaySheet: View {
    @Bindable var log: SessionLog
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let timeZone = log.catalog.gym.timeZone
        NavigationStack {
            DatePicker(
                "Dzień sesji",
                selection: Binding(
                    get: { log.day.date(in: timeZone) },
                    set: { log.day = LocalDate($0, in: timeZone); dismiss() }
                ),
                in: ...log.today.date(in: timeZone),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, .app)
            .tint(Palette.moss)
            .padding(.horizontal)
            .navigationTitle("Dzień sesji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
            .canvasBackground()
        }
    }
}

// MARK: - Tally

private struct TallyCard: View {
    let log: SessionLog

    var body: some View {
        let summary = log.summary
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                tallies(summary)
                Spacer(minLength: 8)
                hardest(summary)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) { tallies(summary) }
                hardest(summary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 14, radius: 18)
    }

    @ViewBuilder
    private func tallies(_ summary: DaySummary) -> some View {
        Tally(result: .flash, count: summary.flashes)
        Tally(result: .top, count: summary.tops)
        Tally(result: .project, count: summary.projects)
    }

    @ViewBuilder
    private func hardest(_ summary: DaySummary) -> some View {
        if let hardest = summary.hardestTop {
            VStack(alignment: .trailing, spacing: 0) {
                Text("najtrudniejszy")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                Text(hardest.label)
                    .font(.display(.title))
                    .foregroundStyle(Palette.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Najtrudniejszy top: \(hardest.label)")
        }
    }
}

private struct Tally: View {
    let result: AscentResult
    let count: Int

    var body: some View {
        VStack(spacing: 2) {
            Pictogram(kind: result.pictogram, size: 24)
            Text("\(count)")
                .font(.display(.title3).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Text(result.polishName.lowercased())
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .frame(minWidth: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.polishName): \(count)")
    }
}

// MARK: - Sectors

/// Sector chips over a pager of sector photos: swipe from wall to wall, or
/// jump with a chip. Each chip counts what is logged on that wall.
private struct SectorPager: View {
    let log: SessionLog
    let sectors: [Sector]
    @Binding var selection: UUID?
    let onDetails: (ActiveProblem) -> Void

    private var current: UUID? { selection ?? sectors.first?.id }

    var body: some View {
        let results = log.results
        let catalog = log.catalog
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sectors) { sector in
                            let count = catalog.problems(in: sector).filter { results[$0.id] != nil }.count
                            FilterChip(isOn: sector.id == current) {
                                withAnimation(.snappy) { selection = sector.id }
                            } content: {
                                Text(count > 0 ? "\(sector.name) · \(count)" : sector.name)
                            }
                            .id(sector.id)
                            .accessibilityLabel(sector.name + (count > 0 ? ", zapisane: \(count)" : ""))
                        }
                    }
                }
                .scrollClipDisabled()
                .onChange(of: current) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(sectors) { sector in
                        SessionSectorPage(log: log, sector: sector, onDetails: onDetails)
                            .containerRelativeFrame(.horizontal)
                            .id(sector.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection)
            .scrollClipDisabled()

            Text("Dotknij pinezki: top → flash → projekt → nic. Przytrzymaj, aby dodać szczegóły.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A sector photo whose pins toggle the day's result.
private struct SessionSectorPage: View {
    let log: SessionLog
    let sector: Sector
    let onDetails: (ActiveProblem) -> Void

    var body: some View {
        let catalog = log.catalog
        let problems = catalog.problems(in: sector)
        let labels = catalog.gradesById.mapValues(\.label)
        let highlighted = catalog.visibleProblemIds
        let results = log.results

        if let photo = catalog.photo(of: sector) {
            CachedPhotoView(photo: photo)
                .aspectRatio(photo.aspectRatio, contentMode: .fit)
                .accessibilityHidden(true)
                .overlay {
                    GeometryReader { proxy in
                        ForEach(problems) { problem in
                            ProblemPin(
                                color: problem.holdColor,
                                label: labels[problem.gradeId],
                                isHighlighted: highlighted.contains(problem.id),
                                sessionResult: results[problem.id]?.result,
                                sectorName: sector.name,
                                isSessionPin: true
                            )
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .onTapGesture { log.cycle(problem) }
                            .onLongPressGesture { onDetails(problem) }
                            .sessionPinAccessibility(log: log, problem: problem, onDetails: onDetails)
                            .sensoryFeedback(.selection, trigger: results[problem.id]?.result)
                            .position(x: problem.pinX * proxy.size.width, y: problem.pinY * proxy.size.height)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.line))
        }
    }
}

// MARK: - Logged

/// What I logged that day, with a way into the details.
private struct LoggedList: View {
    let log: SessionLog
    let onSelect: (ActiveProblem) -> Void

    var body: some View {
        let catalog = log.catalog
        let grades = catalog.gradesById
        let results = log.results
        let logged = catalog.problems.filter { results[$0.id] != nil }

        VStack(alignment: .leading, spacing: 10) {
            Text("Twoja sesja")
                .font(.display(.title3))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(logged) { problem in
                    if let ascent = results[problem.id] {
                        Button { onSelect(problem) } label: {
                            HStack(spacing: 12) {
                                ProblemPin(color: problem.holdColor, label: grades[problem.gradeId]?.label,
                                           sessionResult: ascent.result)
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title(problem, ascent))
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Palette.ink)
                                    Text(details(ascent))
                                        .font(.caption)
                                        .foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.muted)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if problem.id != logged.last?.id {
                            Divider().overlay(Palette.line).padding(.leading, 62)
                        }
                    }
                }
            }
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.line))
        }
    }

    private func title(_ problem: ActiveProblem, _ ascent: Ascent) -> String {
        let sector = log.catalog.sectors.first { $0.id == problem.sectorId }?.name
        return [ascent.result.polishName, sector].compactMap { $0 }.joined(separator: " · ")
    }

    private func details(_ ascent: Ascent) -> String {
        var parts: [String] = []
        if let attempts = ascent.attempts { parts.append("próby: \(attempts.polishName)") }
        if let perceived = ascent.perceivedGrade { parts.append(perceived.polishName.lowercased()) }
        if !ascent.limiters.isEmpty { parts.append(ascent.limiters.map(\.polishName).joined(separator: ", ")) }
        return parts.isEmpty ? "Dodaj szczegóły" : parts.joined(separator: " · ")
    }
}
