import BoulderKit
import Charts
import SwiftUI

/// Shown after "Gotowe" on the session screen: the day in one line
/// ("4 topy · 1 flash · najtrudniejszy: 6 · nowy rekord!"), what was special
/// about it, and how it compares with the last sessions.
struct SessionRecapView: View {
    let recap: SessionRecap
    let gym: Gym

    @Environment(\.dismiss) private var dismiss
    @State private var hasAppeared = false

    init(recap: SessionRecap, gym: Gym) {
        self.recap = recap
        self.gym = gym
    }

    init(log: SessionLog) {
        let catalog = log.catalog
        self.init(
            recap: SessionRecap.make(
                day: log.day,
                dayAscents: log.dayAscents,
                history: catalog.myAscents,
                grades: catalog.gradesById,
                today: log.today
            ),
            gym: catalog.gym
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if !recap.highlights.isEmpty {
                        highlights
                            .fadeUp(0.15)
                    }
                    if recap.recent.count > 1 {
                        StatsCard(title: "Ostatnie sesje", subtitle: comparisonText) {
                            RecentSessionsChart(days: recap.recent, highlighted: recap.day, timeZone: gym.timeZone)
                        }
                        .fadeUp(0.25)
                    }
                    if recap.summary.projects > 0 {
                        HStack(spacing: 10) {
                            Pictogram(kind: .project, size: 24)
                            Text("\(Counted.projects(recap.summary.projects)) czeka na następną sesję.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Button("Gotowe") { dismiss() }
                        .buttonStyle(.pill)
                        .padding(.top, 4)
                }
                .padding()
            }
            .canvasBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: "\(gym.name), \(recap.day.dayAndMonth(in: gym.timeZone)): \(headline)") {
                        Label("Udostępnij", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sensoryFeedback(trigger: hasAppeared) { _, appeared in
            appeared && recap.isRecord ? .success : nil
        }
        .onAppear { hasAppeared = true }
    }

    private var title: String {
        recap.highlights.contains(.firstSession) ? "Pierwsza sesja" : "Sesja nr \(recap.sessionNumber)"
    }

    private var hero: some View {
        VStack(spacing: 10) {
            DrawingView(drawing: .top, drawsOn: true)
                .frame(height: 130)
            Text(headline)
                .font(.display(.title2))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                tally(.flash, recap.summary.flashes)
                tally(.top, recap.summary.tops)
                tally(.project, recap.summary.projects)
            }
        }
        .frame(maxWidth: .infinity)
        .paperCard(padding: 20)
    }

    private func tally(_ result: AscentResult, _ count: Int) -> some View {
        VStack(spacing: 2) {
            Pictogram(kind: result.pictogram, size: 24)
            Text("\(count)").font(.display(.title3).monospacedDigit())
            Text(result.polishName).font(.caption).foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.polishName): \(count)")
    }

    /// "4 topy · 1 flash · najtrudniejszy: 6 · nowy rekord!"
    var headline: String {
        let summary = recap.summary
        var parts: [String] = []
        if summary.tops > 0 { parts.append(Counted.tops(summary.tops)) }
        if summary.flashes > 0 { parts.append(Counted.flashes(summary.flashes)) }
        if summary.tops + summary.flashes == 0 && summary.projects > 0 {
            parts.append(Counted.projects(summary.projects))
        }
        if let hardest = summary.hardestTop { parts.append("najtrudniejszy: \(hardest.label)") }
        if recap.isRecord { parts.append("nowy rekord!") }
        return parts.isEmpty ? "Nic jeszcze nie zapisano" : parts.joined(separator: " · ")
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(recap.highlights, id: \.self) { highlight in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Pictogram(kind: pictogram(for: highlight), size: 26)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    Text(text(for: highlight))
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
    }

    private func pictogram(for highlight: SessionRecap.Highlight) -> Pictogram.Kind {
        switch highlight {
        case .firstSession: .door
        case .gradeRecord: .top
        case .flashRecord: .flash
        case .newSends: .map
        case .aboveAverage: .chalkBag
        case .weekStreak: .reset
        }
    }

    private func text(for highlight: SessionRecap.Highlight) -> String {
        switch highlight {
        case .firstSession:
            "Pierwsza zapisana sesja na tej ściance. Od dziś budujesz swoją piramidę!"
        case let .gradeRecord(grade, previous):
            "Nowy rekord: \(grade.label). Do tej pory Twój najtrudniejszy top to \(previous.label)."
        case let .flashRecord(grade, previous):
            "Najtrudniejszy flash w historii: \(grade.label) (wcześniej \(previous.label))."
        case let .newSends(count):
            "\(Counted.newSends(count)) — problemy zrobione pierwszy raz."
        case let .aboveAverage(difference):
            "O \(Counted.tops(difference)) więcej niż zwykle."
        case let .weekStreak(weeks):
            "\(weeks). tydzień z rzędu na ściance."
        }
    }

    private var comparisonText: String? {
        guard let previous = recap.previous else { return nil }
        var text = "Poprzednio (\(previous.date.dayAndMonth(in: gym.timeZone))): \(Counted.tops(previous.sends))"
        if let average = recap.averageSends {
            text += ", zwykle około \(Counted.tops(Int(average.rounded())))"
        }
        return text + "."
    }
}

/// Sends of the last sessions, this one in full color.
private struct RecentSessionsChart: View {
    let days: [DayTally]
    let highlighted: LocalDate
    let timeZone: TimeZone
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 150

    var body: some View {
        Chart {
            ForEach(days) { day in
                let label = day.date.shortDay(in: timeZone)
                let opacity = day.date == highlighted ? 1 : 0.4
                BarMark(x: .value("Dzień", label), y: .value("Liczba", day.flashes))
                    .foregroundStyle(by: .value("Wynik", "Flash"))
                    .opacity(opacity)
                    .accessibilityLabel(day.date.dayAndMonth(in: timeZone))
                    .accessibilityValue("\(Counted.flashes(day.flashes)), \(Counted.tops(day.tops))")
                BarMark(x: .value("Dzień", label), y: .value("Liczba", day.tops))
                    .foregroundStyle(by: .value("Wynik", "Top"))
                    .opacity(opacity)
                    .accessibilityHidden(true)
            }
        }
        .chartForegroundStyleScale(["Flash": Palette.sun, "Top": Palette.sky])
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Palette.line)
                AxisValueLabel().font(.caption2)
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: height)
    }
}
