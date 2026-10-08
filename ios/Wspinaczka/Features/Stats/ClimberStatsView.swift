import BoulderKit
import Charts
import SwiftUI

/// "Postępy": my grade pyramid, wall coverage, session calendar and what
/// stops me on projects. Everything is private and computed on the phone.
struct StatsTab: View {
    @Environment(AppModel.self) private var app
    @State private var selectedGymId: UUID?

    private var gym: Gym? {
        app.gyms.first { $0.id == selectedGymId } ?? app.gyms.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let gym {
                    ClimberStatsView(gym: gym)
                        .id(gym.id)
                } else {
                    ChalkEmptyState(
                        title: "Brak ścianek",
                        message: "Gdy Twoja ścianka zostanie opublikowana, tutaj zobaczysz swoje postępy.",
                        refresh: { await app.refresh() }
                    )
                }
            }
            .canvasBackground()
            .navigationTitle("Postępy")
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

struct ClimberStatsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: ClimberStatsModel

    init(gym: Gym) {
        _model = State(initialValue: ClimberStatsModel(gym: gym))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !model.hasLoaded && model.catalog.isLoading {
                    DrawingView(drawing: .grip)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    content
                }
            }
            .padding()
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isEmpty {
            WelcomeCard()
                .fadeUp()
        } else {
            OverviewTiles(overview: model.overview)
                .fadeUp()
            StatsCard(title: "Piramida", subtitle: "Różne problemy zrobione na każdej wycenie, najlepszy wynik się liczy.") {
                if model.pyramid.isEmpty {
                    StatsEmptyNote(text: "Na razie same projekty. Pierwszy top zbuduje podstawę piramidy.")
                } else {
                    PyramidChart(levels: model.pyramid)
                }
            }
            .fadeUp(0.05)
        }

        StatsCard(title: "Pokrycie ścianki", subtitle: "Ile z problemów, które teraz wiszą, masz już zrobione.") {
            if model.coverage.isEmpty {
                StatsEmptyNote(text: "Na ściance nie ma jeszcze problemów na zdjęciach.")
            } else {
                CoverageChart(coverage: model.coverage)
            }
        }
        .fadeUp(0.1)

        if !model.isEmpty {
            StatsCard(title: "Kalendarz sesji", subtitle: streakText) {
                SessionCalendarGrid(weeks: model.calendar, today: model.today, timeZone: model.gym.timeZone)
            }
            .fadeUp(0.15)

            StatsCard(title: "Co Cię zatrzymuje", subtitle: weaknessSubtitle) {
                if model.weakness.isEmpty {
                    StatsEmptyNote(text: "Gdy przy projekcie zaznaczysz, co Cię zatrzymało (przytrzymaj pinezkę na ekranie Sesja), zobaczysz tu swoje słabe strony z ostatnich 6 tygodni.")
                } else {
                    WeaknessChart(shares: Array(model.weakness.shares.prefix(6)))
                }
            }
            .fadeUp(0.2)
        }

        if app.access.isStaff(of: model.gym.id) {
            NavigationLink {
                GymStatsView(gym: model.gym)
            } label: {
                HStack(spacing: 12) {
                    Pictogram(kind: .map, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Statystyki ścianki").font(.headline).foregroundStyle(Palette.ink)
                        Text("Anonimowe dane o problemach — dla obsługi ścianki.")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .paperCard()
            }
            .buttonStyle(.plain)
        }

        HStack(spacing: 8) {
            Pictogram(kind: .lock, size: 20)
            Text("Twoje statystyki widzisz tylko Ty.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var streakText: String {
        let current = model.weekStreak
        let longest = model.longestWeekStreak
        let now = current > 0 ? "Seria: \(Counted.weeks(current)) z rzędu." : "Wpadnij w tym tygodniu, żeby zacząć serię."
        return longest > current ? "\(now) Najdłuższa: \(Counted.weeks(longest))." : now
    }

    private var weaknessSubtitle: String {
        let profile = model.weakness
        guard profile.projects > 0 else { return "Projekty z ostatnich 6 tygodni." }
        return "Na podstawie \(Counted.projects(profile.projects)) z ostatnich 6 tygodni (z tagami: \(profile.taggedProjects))."
    }

    private func reload() async {
        do { try await model.load() } catch { app.report(error) }
    }
}

/// First visit: what this screen will show after the first session.
private struct WelcomeCard: View {
    var body: some View {
        VStack(spacing: 10) {
            DrawingView(drawing: .chalk)
                .frame(height: 130)
            Text("Tu urosną Twoje postępy")
                .font(.display(.title3))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text("Po pierwszej sesji zobaczysz tu swoją piramidę wycen, kalendarz wizyt i serię tygodni, a z czasem także to, co najczęściej zatrzymuje Cię na projektach.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Text("Po wizycie na ściance otwórz zakładkę Sesja i dotknij pinezek tego, co udało się zrobić.")
                .font(.footnote)
                .foregroundStyle(Palette.mossDark)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .paperCard(padding: 20)
    }
}

private struct OverviewTiles: View {
    let overview: ClimberOverview
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 140), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            StatTile(value: "\(overview.sends)", caption: "zrobione problemy", pictogram: .top)
            StatTile(value: "\(overview.flashes)", caption: "flashe", pictogram: .flash)
            StatTile(value: overview.hardestTop?.label ?? "—", caption: "najtrudniejszy top")
            StatTile(value: "\(overview.climbingDays)", caption: "dni na ściance")
        }
    }
}

// MARK: - Charts

/// The pyramid centred like a real one: flashes in the middle in yellow,
/// tops around them in blue, hardest grade on top. Missing steps stay empty.
struct PyramidChart: View {
    let levels: [PyramidLevel]
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 30

    var body: some View {
        let widest = Double(max(levels.map(\.total).max() ?? 1, 1))
        Chart {
            ForEach(levels) { level in
                let half = Double(level.total) / 2
                let label = level.grade.label
                if level.flashes > 0 {
                    BarMark(xStart: .value("Od", -half), xEnd: .value("Do", -half + Double(level.flashes)),
                            y: .value("Wycena", label))
                        .foregroundStyle(by: .value("Wynik", "Flash"))
                        .clipShape(.rect(cornerRadius: 4))
                        .accessibilityLabel("Wycena \(label), flashe")
                        .accessibilityValue("\(level.flashes)")
                }
                if level.tops > 0 {
                    BarMark(xStart: .value("Od", -half + Double(level.flashes)), xEnd: .value("Do", half),
                            y: .value("Wycena", label))
                        .foregroundStyle(by: .value("Wynik", "Top"))
                        .clipShape(.rect(cornerRadius: 4))
                        .accessibilityLabel("Wycena \(label), topy")
                        .accessibilityValue("\(level.tops)")
                }
                PointMark(x: .value("Do", max(half, 0.15)), y: .value("Wycena", label))
                    .symbolSize(0)
                    .annotation(position: .trailing, spacing: 6) {
                        Text("\(level.total)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(level.total == 0 ? Palette.muted : Palette.ink)
                    }
                    .accessibilityHidden(level.total > 0)
                    .accessibilityLabel("Wycena \(label)")
                    .accessibilityValue("nic jeszcze")
            }
        }
        .chartForegroundStyleScale(["Flash": Palette.sun, "Top": Palette.sky])
        .chartXScale(domain: (-widest / 2 - 0.3)...(widest / 2 + 1))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel(centered: true)
                    .font(.display(.subheadline))
                    .foregroundStyle(Palette.ink)
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: rowHeight * CGFloat(levels.count) + 36)
    }
}

/// Active problems per grade, the done part in moss.
struct CoverageChart: View {
    let coverage: [GradeCoverage]
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 170

    var body: some View {
        Chart(coverage) { entry in
            BarMark(x: .value("Wycena", entry.grade.label), y: .value("Problemy", entry.topped))
                .foregroundStyle(Palette.moss)
                .accessibilityLabel("Wycena \(entry.grade.label)")
                .accessibilityValue("\(entry.topped) z \(entry.active) zrobione")
            BarMark(x: .value("Wycena", entry.grade.label), y: .value("Problemy", entry.active - entry.topped))
                .foregroundStyle(Palette.mat)
                .annotation(position: .top, spacing: 3) {
                    Text("\(entry.topped)/\(entry.active)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                }
                .accessibilityHidden(true)
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.display(.subheadline))
                    .foregroundStyle(Palette.ink)
            }
        }
        .frame(height: height)
    }
}

/// Share of each limiter on recent projects.
struct WeaknessChart: View {
    let shares: [LimiterShare]

    var body: some View {
        LabeledBarChart(
            rows: shares.map { share in
                LabeledBarChart.Row(id: share.limiter.rawValue, name: share.limiter.polishName,
                                    value: share.share, valueText: share.share.percentText,
                                    spokenValue: "\(share.share.percentText), \(share.count) razy")
            },
            maximum: 1,
            color: Palette.plum
        )
    }
}

/// Horizontal bars with the name above each bar, so long Polish names
/// never fight the bars for room at large text sizes.
struct LabeledBarChart: View {
    struct Row: Identifiable {
        let id: String
        let name: String
        let value: Double
        let valueText: String
        let spokenValue: String
    }

    let rows: [Row]
    let maximum: Double
    let color: Color
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 48

    var body: some View {
        Chart(rows) { row in
            BarMark(x: .value("Wartość", row.value), y: .value("Nazwa", row.id), height: .fixed(12))
                .foregroundStyle(color)
                .clipShape(Capsule())
                .annotation(position: .top, alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                }
                .annotation(position: .trailing, spacing: 6) {
                    Text(row.valueText)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                }
                .accessibilityLabel(row.name)
                .accessibilityValue(row.spokenValue)
        }
        .chartXScale(domain: 0...(max(maximum, 0.0001) * 1.18))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: rowHeight * CGFloat(rows.count))
    }
}

// MARK: - Calendar

/// The last weeks, Monday to Sunday; a filled dot for each climbing day,
/// darker with more logged problems.
struct SessionCalendarGrid: View {
    let weeks: [CalendarWeek]
    let today: LocalDate
    let timeZone: TimeZone
    @ScaledMetric(relativeTo: .body) private var cell: CGFloat = 26

    private static let weekdays = ["Pn", "Wt", "Śr", "Cz", "Pt", "So", "Nd"]
    private static let spokenWeekdays = ["poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota", "niedziela"]

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                ForEach(Self.weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(weeks) { week in
                GridRow {
                    Text(week.start.shortDay(in: timeZone))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .fixedSize()
                        .gridColumnAlignment(.trailing)
                    ForEach(week.days) { day in
                        dayCell(day)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tydzień od \(week.start.dayAndMonth(in: timeZone))")
                .accessibilityValue(weekValue(week))
            }
        }
        // Seven columns of dots have to fit the phone; the labels stop
        // growing at the largest standard size (VoiceOver reads each week).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let intensity = min(1, 0.45 + Double(day.ascents) * 0.08)
        return ZStack {
            Circle()
                .fill(day.climbed ? Palette.moss.opacity(intensity) : Palette.mat.opacity(day.isFuture ? 0.35 : 1))
            if day.date == today {
                Circle().stroke(Palette.ink, lineWidth: 1.5)
            }
        }
        .frame(maxWidth: cell, maxHeight: cell)
        .aspectRatio(1, contentMode: .fit)
    }

    private func weekValue(_ week: CalendarWeek) -> String {
        let days = week.days.filter(\.climbed)
        guard !days.isEmpty else { return "bez sesji" }
        let names = days.map { Self.spokenWeekdays[SessionCalendar.weekday(of: $0.date)] }
        return "\(Counted.sessions(days.count)): \(names.joined(separator: ", "))"
    }
}
