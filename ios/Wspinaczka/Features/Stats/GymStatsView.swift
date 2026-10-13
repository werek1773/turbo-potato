import BoulderKit
import Charts
import Observation
import SwiftUI

/// The anonymous daily snapshot of one gym joined with its wall.
@MainActor
@Observable
final class GymStatsModel {
    let catalog: GymCatalog
    private(set) var stats: [ProblemStats] = []
    private(set) var hasLoaded = false

    init(gym: Gym, backend: Backend = .shared) {
        catalog = GymCatalog(gym: gym, backend: backend)
    }

    func load() async throws {
        let backend = catalog.backend, gymId = catalog.gym.id
        async let stats = backend.problemStats(gymId: gymId)
        try await catalog.load()
        self.stats = try await stats
        hasLoaded = true
    }

    var insights: GymInsights {
        GymInsights.make(stats: stats, problems: catalog.problems, grades: catalog.grades)
    }

    var sectorNames: [UUID: String] {
        Dictionary(catalog.sectors.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Statistics of a gym for its managers and routesetters (flow #9): how the
/// community grades the problems, what gets climbed and sent, and what stops
/// people. Built only from the anonymous daily snapshot.
struct GymStatsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: GymStatsModel

    init(gym: Gym) {
        _model = State(initialValue: GymStatsModel(gym: gym))
    }

    private var gym: Gym { model.catalog.gym }

    var body: some View {
        Group {
            if app.access.isStaff(of: gym.id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        PrivacyNote()
                        content
                    }
                    .padding()
                }
                .task { await reload() }
                .refreshable { await reload() }
            } else {
                ContentUnavailableView(
                    "Tylko dla obsługi ścianki",
                    systemImage: "lock",
                    description: Text("Statystyki ścianki widzą jej managerowie i routesetterzy.")
                )
            }
        }
        .canvasBackground()
        .navigationTitle("Statystyki ścianki")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded && model.catalog.isLoading {
            DrawingView(drawing: .grip)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
        } else {
            GymStatsContent(insights: model.insights, sectorNames: model.sectorNames)
        }
    }

    private func reload() async {
        do { try await model.load() } catch { app.report(error) }
    }
}

/// The cards of the gym statistics for a loaded snapshot.
struct GymStatsContent: View {
    let insights: GymInsights
    let sectorNames: [UUID: String]

    private static let listLimit = 8

    var body: some View {
        if insights.isEmpty {
            StatsCard(title: "Jeszcze za mało danych") {
                StatsEmptyNote(text: "Problem pojawi się tu, gdy co najmniej 5 osób zapisze go w swoich sesjach, a od przejść minie kilka dni. Migawka liczy się raz na dobę.")
            }
        } else {
            summary(insights)

            StatsCard(title: "Odsetek przejść", subtitle: "Ile osób, które próbowały, zrobiło problem — dla każdej wyceny.") {
                SendRateChart(grades: insights.byGrade.filter { $0.climbers > 0 })
            }

            StatsCard(title: "Wycena społeczności", subtitle: "Liczba problemów, które wspinacze uznali za miękkie, w sam raz lub twarde.") {
                if insights.byGrade.allSatisfy({ $0.verdicts == 0 }) {
                    StatsEmptyNote(text: "Za mało ocen wyceny — każda odpowiedź musi pochodzić od co najmniej 5 osób.")
                } else {
                    CommunityGradeChart(grades: insights.byGrade.filter { $0.verdicts > 0 })
                }
            }

            StatsCard(title: "Najpopularniejsze", subtitle: "Najwięcej osób w migawce.") {
                ProblemList(rows: Array(insights.popular.prefix(Self.listLimit)), sectorNames: sectorNames) { row in
                    popularityDetail(row)
                }
            }

            let hard = insights.perceived(.hard), soft = insights.perceived(.soft)
            if !hard.isEmpty || !soft.isEmpty {
                StatsCard(title: "Wycena do sprawdzenia", subtitle: "Problemy, które większość uznała za twardsze lub miększe niż wycena.") {
                    if !hard.isEmpty {
                        Text("Twardsze").font(.headline).foregroundStyle(Palette.coral)
                        ProblemList(rows: Array(hard.prefix(Self.listLimit)), sectorNames: sectorNames) { verdictDetail($0) }
                    }
                    if !soft.isEmpty {
                        Text("Miększe").font(.headline).foregroundStyle(Palette.mossDark)
                        ProblemList(rows: Array(soft.prefix(Self.listLimit)), sectorNames: sectorNames) { verdictDetail($0) }
                    }
                }
            }

            StatsCard(title: "Co zatrzymuje wspinaczy", subtitle: "Najczęstsze tagi przy projektach.") {
                if insights.limiterTotals.isEmpty {
                    StatsEmptyNote(text: "Żaden tag nie został jeszcze wskazany przez co najmniej 5 osób przy jednym problemie.")
                } else {
                    LimiterTotalsChart(totals: Array(insights.limiterTotals.prefix(6)))
                    ProblemList(rows: Array(insights.limiterHeavy.prefix(Self.listLimit)), sectorNames: sectorNames) { row in
                        row.limiters.prefix(2).map { "\($0.limiter.polishName) (\($0.climbers)+)" }.joined(separator: " · ")
                    }
                }
            }
        }
    }

    private func summary(_ insights: GymInsights) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dane dla \(insights.problems.count) z \(Counted.problems(insights.activeProblems)) na ścianie")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            if let computedAt = insights.computedAt {
                Text("Migawka z \(computedAt.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: .app)))")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private func popularityDetail(_ row: ProblemInsight) -> String {
        var parts: [String] = []
        if let climbers = row.climbers { parts.append("\(climbers)+ osób") }
        if let rate = row.sendRate {
            parts.append("\(rate.percentText) przejść")
        } else {
            parts.append("mniej niż 5 topów")
        }
        if let flash = row.flashRate { parts.append("\(flash.percentText) flash") }
        return parts.joined(separator: " · ")
    }

    private func verdictDetail(_ row: ProblemInsight) -> String {
        let stats = row.stats
        let counts: [(String, Int?)] = [("miękka", stats.perceivedSoft), ("w sam raz", stats.perceivedOk),
                                        ("twarda", stats.perceivedHard)]
        return counts.compactMap { name, count in count.map { "\(name): \($0)+" } }.joined(separator: " · ")
    }

}

/// What the numbers are and what they are not.
private struct PrivacyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Pictogram(kind: .lock, size: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text("Anonimowe, dobowe, z opóźnieniem")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text("Migawka liczona raz na dobę z przejść starszych niż 3 dni. Każda liczba to co najmniej 5 osób, zaokrąglona w dół do 5 — komórki z mniejszą liczbą są ukryte. Nie liczymy obsługi ścianki ani osób, które wypisały się ze statystyk. Samopoczucie i notatki nigdy tu nie trafiają.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .paperCard()
        .accessibilityElement(children: .combine)
    }
}

/// Rows of problems: pin, sector and a detail line.
private struct ProblemList: View {
    let rows: [ProblemInsight]
    let sectorNames: [UUID: String]
    let detail: (ProblemInsight) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    ProblemPin(color: row.problem.holdColor, label: row.grade?.label)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(row))
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.ink)
                        Text(detail(row))
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                if row.id != rows.last?.id { Divider() }
            }
        }
    }

    private func title(_ row: ProblemInsight) -> String {
        let name = row.problem.name ?? "\(row.problem.holdColor.polishName.capitalized) \(row.grade?.label ?? "")"
        guard let sector = sectorNames[row.problem.sectorId] else { return name }
        return "\(name) · \(sector)"
    }
}

private struct SendRateChart: View {
    let grades: [GradeInsight]
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 180

    var body: some View {
        Chart(grades) { entry in
            if let rate = entry.sendRate {
                BarMark(x: .value("Wycena", entry.grade.label), y: .value("Odsetek przejść", rate))
                    .foregroundStyle(Palette.sky)
                    .clipShape(.rect(cornerRadius: 4))
                    .annotation(position: .top, spacing: 3) {
                        Text(rate.percentText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Palette.muted)
                    }
                    .accessibilityLabel("Wycena \(entry.grade.label)")
                    .accessibilityValue("\(rate.percentText) przejść, \(entry.climbers) lub więcej osób, \(Counted.problems(entry.problemsWithData)) z danymi")
            }
        }
        .chartYScale(domain: 0...1.1)
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

private struct CommunityGradeChart: View {
    let grades: [GradeInsight]
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 180

    var body: some View {
        Chart {
            ForEach(grades) { entry in
                ForEach(verdicts(entry), id: \.0) { verdict, count in
                    BarMark(x: .value("Wycena", entry.grade.label), y: .value("Problemy", count))
                        .foregroundStyle(by: .value("Odczucie", verdict.polishName))
                        .accessibilityLabel("Wycena \(entry.grade.label), \(verdict.polishName.lowercased())")
                        .accessibilityValue(Counted.problems(count))
                }
            }
        }
        .chartForegroundStyleScale([
            PerceivedGrade.soft.polishName: Palette.mossLight,
            PerceivedGrade.ok.polishName: Palette.mustard,
            PerceivedGrade.hard.polishName: Palette.coral,
        ])
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.display(.subheadline))
                    .foregroundStyle(Palette.ink)
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: height)
    }

    private func verdicts(_ entry: GradeInsight) -> [(PerceivedGrade, Int)] {
        [(.soft, entry.soft), (.ok, entry.ok), (.hard, entry.hard)].filter { $0.1 > 0 }
    }
}

private struct LimiterTotalsChart: View {
    let totals: [LimiterCount]

    var body: some View {
        LabeledBarChart(
            rows: totals.map { entry in
                LabeledBarChart.Row(id: entry.limiter.rawValue, name: entry.limiter.polishName,
                                    value: Double(entry.climbers), valueText: "\(entry.climbers)+",
                                    spokenValue: "co najmniej \(entry.climbers) zgłoszeń")
            },
            maximum: Double(totals.map(\.climbers).max() ?? 1),
            color: Palette.plum
        )
    }
}
