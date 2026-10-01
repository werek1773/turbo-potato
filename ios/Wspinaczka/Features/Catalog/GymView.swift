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
            VStack(alignment: .leading, spacing: 18) {
                if !catalog.upcomingResets.isEmpty {
                    UpcomingResetsBanner(resets: catalog.upcomingResets)
                }
                if !catalog.coverage.isEmpty {
                    GradeFilterBar(catalog: catalog)
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
                        Label("Dotknij ściany", systemImage: "hand.tap")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
            .padding()
        }
        .canvasBackground()
        .overlay {
            if catalog.sectors.isEmpty {
                if catalog.isLoading {
                    HoldMark(motion: .working).frame(width: 44)
                } else {
                    ContentUnavailableView(
                        "Brak sektorów",
                        systemImage: "square.grid.2x2",
                        description: Text("Routesetterzy jeszcze nie dodali sektorów tej ścianki.")
                    )
                }
            }
        }
        .navigationTitle(catalog.gym.name)
        .navigationDestination(item: $openSector) { route in
            SectorDetailView(catalog: catalog, sectorId: route.id)
                .navigationTransition(.zoom(sourceID: route.id, in: zoom))
        }
        .toolbar {
            if app.access.isManager(of: catalog.gym.id) {
                Button("Dodaj sektor", systemImage: "plus") {
                    newSectorArea = catalog.areas.last?.name ?? ""
                    isAddingSector = true
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

    private func reload() async {
        do { try await catalog.load() } catch { app.report(error) }
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
                    .font(.serif(.title2))
                Spacer()
                if count > 0 {
                    Text("\(topped) z \(count) zrobione")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
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
        .paperCard(radius: 24)
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
                            .font(.serif(.title3))
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
                        .foregroundStyle(reset.daysLeft <= 2 ? Palette.mustard : .secondary)
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
