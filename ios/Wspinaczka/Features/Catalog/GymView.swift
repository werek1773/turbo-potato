import BoulderKit
import SwiftUI

/// A gym: its plan drawn like the reset board. Tap a wall to peek at the
/// sector, then open it.
struct GymView: View {
    @Environment(AppModel.self) private var app
    @State private var catalog: GymCatalog
    @State private var isAddingSector = false
    @State private var newSectorName = ""
    @State private var newSectorArea = ""
    @State private var selection: UUID?
    @State private var openSector: SectorRoute?
    @Namespace private var zoom

    init(gym: Gym) {
        _catalog = State(initialValue: GymCatalog(gym: gym, backend: Backend.shared))
    }

    private var selectedSector: Sector? {
        selection.flatMap { id in catalog.sectors.first { $0.id == id } }
    }

    var body: some View {
        ScrollView {
            content
                .padding()
        }
        .canvasBackground()
        .overlay {
            if catalog.sectors.isEmpty {
                if catalog.isLoading {
                    DrawingView(drawing: .grip)
                        .frame(width: 140)
                } else {
                    VStack(spacing: 8) {
                        DrawingView(drawing: .chalk)
                            .frame(height: 140)
                        Text("Brak sektorów")
                            .font(.display(.title3))
                        Text("Routesetterzy jeszcze nie dodali sektorów tej ścianki.")
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                }
            }
        }
        .navigationTitle(catalog.gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openSector) { route in
            SectorDetailView(catalog: catalog, sectorId: route.id)
                .navigationTransition(.zoom(sourceID: route.id, in: zoom))
        }
        .toolbar {
            // The header below shows the name; the bar keeps only actions.
            ToolbarItem(placement: .principal) { EmptyView() }
            if app.access.isManager(of: catalog.gym.id) {
                ToolbarItem(placement: .primaryAction) {
                    Button("Dodaj sektor", systemImage: "plus") {
                        newSectorArea = catalog.areas.last?.name ?? ""
                        isAddingSector = true
                    }
                }
            }
        }
        .alert("Nowy sektor", isPresented: $isAddingSector) {
            TextField("Nazwa, np. Połóg", text: $newSectorName)
            TextField("Sala, np. Duża sala", text: $newSectorArea)
            Button("Dodaj") {
                let name = newSectorName
                let area = newSectorArea
                newSectorName = ""
                Task {
                    do { try await catalog.addSector(named: name, area: area) } catch { app.report(error) }
                }
            }
            Button("Anuluj", role: .cancel) { newSectorName = "" }
        } message: {
            Text("Sektor trafi na koniec trasy po ściance.")
        }
        .task { await reload() }
        .refreshable { await reload() }
    }


    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            GymHeader(catalog: catalog) { sector in
                withAnimation(.snappy) { selection = sector.id }
            }
            if !catalog.coverage.isEmpty {
                GradeRow(catalog: catalog)
            }
            if let plan = catalog.gym.floorPlan {
                GymMapView(
                    plan: plan,
                    sectors: catalog.sectors,
                    style: { catalog.mapStyle(for: $0) },
                    dots: { catalog.mapDots(for: $0) },
                    selection: $selection.animation(.snappy)
                )
                .padding(.vertical, 4)

                if let sector = selectedSector {
                    SectorPeekCard(catalog: catalog, sector: sector) {
                        openSector = SectorRoute(id: sector.id)
                    }
                    .matchedTransitionSource(id: sector.id, in: zoom)
                    .id(sector.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                } else if !catalog.sectors.isEmpty {
                    Text("Dotknij ściany, żeby zobaczyć jej problemy.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
                DisclosureGroup("Wszystkie sektory") {
                    SectorList(catalog: catalog) { openSector = SectorRoute(id: $0.id) }
                        .padding(.top, 8)
                }
                .tint(Palette.ink)
            } else {
                SectorList(catalog: catalog) { openSector = SectorRoute(id: $0.id) }
            }
        }
    }

    private func reload() async {
        do { try await catalog.load() } catch { app.report(error) }
    }
}

/// The gym's name and one sentence on what matters today: the walls reset
/// next and what is new since the last visit. Both are links: each wall
/// shows itself on the map, the new problems filter the map.
private struct GymHeader: View {
    @Bindable var catalog: GymCatalog
    let onShowSector: (Sector) -> Void

    private var newSinceVisit: Int? {
        guard let lastVisit = catalog.lastVisit else { return nil }
        return catalog.problems.filter { ClimbingDay.localDate(for: $0.setAt, in: catalog.gym.timeZone) > lastVisit }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(catalog.gym.name)
                .font(.display(.largeTitle))
                .foregroundStyle(Palette.ink)
            if let sentence {
                Text(sentence)
                    .font(.body)
                    .foregroundStyle(Palette.muted)
                    .tint(Palette.mossDark)
                    .environment(\.openURL, OpenURLAction { url in
                        handle(url)
                        return .handled
                    })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sentence: AttributedString? {
        var parts: [AttributedString] = []
        if let next = catalog.upcomingResets.first {
            // Every wall reset that day: "Połóg i Trójkąt".
            let walls = catalog.upcomingResets.filter { $0.date == next.date }.map(\.sector)
            var part = AttributedString("Przykrętka \(ResetBadge.relative(next.daysLeft, date: next.date)): ")
            for (index, sector) in walls.enumerated() {
                if index > 0 { part += AttributedString(index == walls.count - 1 ? " i " : ", ") }
                part += link(sector.name, to: "reset/\(sector.id.uuidString)")
            }
            part += AttributedString(".")
            parts.append(part)
        }
        if let count = newSinceVisit, count > 0 {
            var part = link(Self.newProblems(count), to: "new")
            part += AttributedString(" od Twojej ostatniej wizyty.")
            parts.append(part)
        }
        guard !parts.isEmpty else { return nil }
        return parts.dropFirst().reduce(parts[0]) { $0 + AttributedString(" ") + $1 }
    }

    private func link(_ text: String, to target: String) -> AttributedString {
        var part = AttributedString(text)
        part.link = URL(string: "wspinaczka-gym://\(target)")
        part.inlinePresentationIntent = .stronglyEmphasized
        return part
    }

    private func handle(_ url: URL) {
        switch url.host() {
        case "reset":
            let id = UUID(uuidString: url.lastPathComponent)
            if let sector = catalog.sectors.first(where: { $0.id == id }) { onShowSector(sector) }
        case "new":
            catalog.filter.gradeOrders = nil
            catalog.filter.setAfter = catalog.filter.setAfter == nil ? catalog.lastVisit : nil
        default:
            break
        }
    }

    /// "1 nowy", "3 nowe", "7 nowych".
    static func newProblems(_ count: Int) -> String {
        let lastTwo = count % 100, last = count % 10
        if count == 1 { return "1 nowy problem" }
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "\(count) nowe problemy" }
        return "\(count) nowych problemów"
    }
}

/// Grades as plain numbers; the chosen one gets a pen circle drawn around it.
struct GradeRow: View {
    @Bindable var catalog: GymCatalog

    private var grades: [Grade] {
        catalog.coverage.map(\.grade)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(grades) { grade in
                let range = grade.sortOrder...grade.sortOrder
                let isOn = catalog.filter.gradeOrders == range
                Button {
                    catalog.filter.setAfter = nil
                    catalog.filter.gradeOrders = isOn ? nil : range
                } label: {
                    Text(grade.label)
                        .font(.display(.title3))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 34, height: 38)
                        .background {
                            if isOn {
                                PenCircle()
                                    .frame(width: 46, height: 46)
                                    .id(grade.id)
                            }
                        }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Wycena \(grade.label)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: catalog.filter.gradeOrders)
    }
}

/// A circle drawn around something with a pen, in three strokes at 8 fps.
struct PenCircle: View {
    private static let loop = InkPath("M30 9 C20 6 8 11 7 22 C6 33 16 39 25 38 C35 37 40 29 38 19 C36 11 28 7 20 9")

    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: start, by: 1 / StopMotion.fps)) { timeline in
            let frame = reduceMotion ? 3 : StopMotion.frame(at: timeline.date, since: start)
            Canvas { context, size in
                let scale = min(size.width, size.height) / 44
                context.scaleBy(x: scale, y: scale)
                let shown = min(1, CGFloat(frame + 1) / 3)
                let path = Self.loop.path(frame: reduceMotion ? 0 : frame, boil: 1.2, salt: 77).trimmedPath(from: 0, to: shown)
                context.stroke(path, with: .color(Palette.moss),
                               style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SectorRoute: Hashable, Identifiable {
    let id: UUID
}

/// What you see after tapping a wall: its photo with pins and progress.
private struct SectorPeekCard: View {
    let catalog: GymCatalog
    let sector: Sector
    let onOpen: () -> Void

    var body: some View {
        let count = catalog.problems(in: sector).count
        let topped = catalog.toppedCount(in: sector)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(sector.name)
                    .font(.display(.title3))
                Spacer()
                if count > 0 {
                    Text("\(topped) z \(count) zrobione")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                        .contentTransition(.numericText())
                }
            }
            if let reset = catalog.upcomingReset(for: sector) {
                ResetBadge(reset: reset)
            }
            if let photo = catalog.photo(of: sector) {
                SectorPhotoView(
                    photo: photo,
                    problems: catalog.problems(in: sector),
                    highlighted: catalog.visibleProblemIds,
                    topped: catalog.toppedProblemIds
                )
                .frame(maxHeight: 220)
            } else {
                Text("Tej ściany nie ma jeszcze na zdjęciu.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Zobacz problemy", action: onOpen)
                .buttonStyle(.pill)
        }
    }
}

/// One line per sector, grouped by room, in walking order.
private struct SectorList: View {
    let catalog: GymCatalog
    let onSelect: (Sector) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(catalog.areas) { area in
                VStack(alignment: .leading, spacing: 0) {
                    if let name = area.name {
                        Text(name)
                            .font(.display(.title3))
                            .padding(.bottom, 6)
                    }
                    ForEach(area.sectors) { sector in
                        Button { onSelect(sector) } label: {
                            SectorRow(catalog: catalog, sector: sector)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct SectorRow: View {
    let catalog: GymCatalog
    let sector: Sector

    var body: some View {
        let count = catalog.problems(in: sector).count
        let topped = catalog.toppedCount(in: sector)
        let style = catalog.mapStyle(for: sector)
        HStack(spacing: 12) {
            Capsule()
                .fill(style.color)
                .frame(width: 6, height: 28)
                .opacity(style.isDimmed ? 0.3 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(sector.name).font(.body.weight(.medium))
                if let reset = catalog.upcomingReset(for: sector) {
                    Text("Przykrętka \(ResetBadge.relative(reset.daysLeft, date: reset.date))")
                        .font(.caption)
                        .foregroundStyle(reset.daysLeft <= 2 ? Palette.mustardText : Palette.muted)
                } else if catalog.photo(of: sector) == nil {
                    Text("Brak zdjęcia").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if count > 0 {
                Text("\(topped)/\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct PinEditorTarget: Identifiable {
    let sectorId: UUID
    var id: UUID { sectorId }
}
