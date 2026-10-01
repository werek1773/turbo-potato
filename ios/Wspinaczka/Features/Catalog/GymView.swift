import BoulderKit
import SwiftUI

/// A gym: the map of its walls, filters and a compact list of sectors.
struct GymView: View {
    @Environment(AppModel.self) private var app
    @State private var catalog: GymCatalog
    @State private var isAddingSector = false
    @State private var newSectorName = ""
    @State private var newSectorArea = ""
    @State private var openSector: SectorRoute?

    init(gym: Gym) {
        _catalog = State(initialValue: GymCatalog(gym: gym, backend: Backend.shared))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
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
                        onSelect: { openSector = SectorRoute(id: $0.id) }
                    )
                    .padding(.vertical, 8)
                    Text("Dotknij ściany, aby zobaczyć jej problemy.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                SectorList(catalog: catalog) { openSector = SectorRoute(id: $0.id) }
            }
            .padding()
        }
        .overlay {
            if catalog.sectors.isEmpty && !catalog.isLoading {
                ContentUnavailableView(
                    "Brak sektorów",
                    systemImage: "square.grid.2x2",
                    description: Text("Routesetterzy jeszcze nie dodali sektorów tej ścianki.")
                )
            }
        }
        .navigationTitle(catalog.gym.name)
        .navigationDestination(item: $openSector) { route in
            SectorDetailView(catalog: catalog, sectorId: route.id)
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

/// One line per sector, grouped by room, in walking order.
private struct SectorList: View {
    let catalog: GymCatalog
    let onSelect: (Sector) -> Void

    var body: some View {
        ForEach(catalog.areas) { area in
            VStack(alignment: .leading, spacing: 0) {
                if let name = area.name {
                    Text(name)
                        .font(.title3.bold())
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
                        .foregroundStyle(reset.daysLeft <= 2 ? .orange : .secondary)
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
