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
                GymHeader(catalog: catalog) { sector in
                    withAnimation(.snappy) { selection = sector.id }
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

/// Name, address and what matters today: the next reset and new problems.
private struct GymHeader: View {
    @Bindable var catalog: GymCatalog
    let onShowSector: (Sector) -> Void

    private var newSinceVisit: Int? {
        guard let lastVisit = catalog.lastVisit else { return nil }
        return catalog.problems.filter { ClimbingDay.localDate(for: $0.setAt, in: catalog.gym.timeZone) > lastVisit }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let address = catalog.gym.address {
                    Text([catalog.gym.city, address].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                Text(catalog.gym.name)
                    .font(.display(.largeTitle))
                    .foregroundStyle(Palette.ink)
            }
            HStack(spacing: 8) {
                if let reset = catalog.upcomingResets.first {
                    Tile(title: "Przykrętka",
                         value: "\(reset.sector.name) · \(ResetBadge.relative(reset.daysLeft, date: reset.date))",
                         valueColor: Palette.mustardText, isOn: false) {
                        onShowSector(reset.sector)
                    }
                } else {
                    Tile(title: "Przykrętka", value: "Brak zapowiedzi", valueColor: Palette.muted, isOn: false, action: nil)
                }
                if let newCount = newSinceVisit, let lastVisit = catalog.lastVisit {
                    Tile(title: "Nowe od ostatniej wizyty",
                         value: newCount == 1 ? "1 problem" : "\(newCount) problemów",
                         valueColor: Palette.ink, isOn: catalog.filter.setAfter != nil) {
                        catalog.filter.setAfter = catalog.filter.setAfter == nil ? lastVisit : nil
                    }
                } else {
                    Tile(title: "Na ścianach", value: "\(catalog.problems.count) problemów",
                         valueColor: Palette.ink, isOn: false, action: nil)
                }
            }
        }
    }

    private struct Tile: View {
        let title: String
        let value: String
        let valueColor: Color
        let isOn: Bool
        let action: (() -> Void)?

        var body: some View {
            Button {
                action?()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(isOn ? Palette.mat : Palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isOn ? Palette.moss : Palette.line))
            }
            .buttonStyle(.plain)
            .disabled(action == nil)
        }
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
