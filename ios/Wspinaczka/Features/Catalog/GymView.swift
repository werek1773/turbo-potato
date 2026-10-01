import BoulderKit
import SwiftUI

struct GymView: View {
    @Environment(AppModel.self) private var app
    @State private var catalog: GymCatalog
    @State private var isAddingSector = false
    @State private var newSectorName = ""
    @State private var newSectorArea = ""
    @State private var plannedSector: Sector?
    @State private var photoSector: Sector?
    @State private var pinEditor: PinEditorTarget?
    @State private var editorAfterPhoto: UUID?

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
                ForEach(catalog.areas) { area in
                    if let name = area.name {
                        Text(name)
                            .font(.title2.bold())
                            .padding(.top, 8)
                    }
                    ForEach(area.sectors) { sector in
                        SectorCard(
                            sector: sector,
                            photo: sector.currentPhotoId.flatMap { catalog.photos[$0] },
                            problems: catalog.problems(in: sector),
                            highlighted: catalog.visibleProblemIds,
                            topped: catalog.toppedProblemIds,
                            gradeLabels: catalog.gradesById.mapValues(\.label),
                            upcomingReset: catalog.upcomingReset(for: sector),
                            staffActions: app.access.isStaff(of: catalog.gym.id)
                                ? SectorStaffActions(
                                    newPhoto: { photoSector = sector },
                                    editPins: { pinEditor = PinEditorTarget(sectorId: sector.id) },
                                    planReset: { plannedSector = sector }
                                )
                                : nil
                        )
                    }
                }
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
        .sheet(item: $plannedSector) { sector in
            NextResetSheet(sector: sector, timeZone: catalog.gym.timeZone) { date in
                do {
                    try await catalog.setNextReset(for: sector, on: date)
                    return true
                } catch {
                    app.report(error)
                    return false
                }
            }
        }
        .sheet(item: $photoSector, onDismiss: {
            // Open the pin editor only once the photo sheet is fully gone.
            if let sectorId = editorAfterPhoto {
                editorAfterPhoto = nil
                pinEditor = PinEditorTarget(sectorId: sectorId)
            }
        }) { sector in
            NewSectorPhotoView(catalog: catalog, sector: sector) {
                editorAfterPhoto = sector.id
            }
        }
        .fullScreenCover(item: $pinEditor) { target in
            PinEditorView(catalog: catalog, sectorId: target.sectorId)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        do { try await catalog.load() } catch { app.report(error) }
    }
}

/// "4 · 7/12" chips: tap a grade to show only its problems.
struct GradeFilterBar: View {
    @Bindable var catalog: GymCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(catalog.coverage) { level in
                        let selected = catalog.filter.gradeOrders == level.grade.sortOrder...level.grade.sortOrder
                        Button {
                            catalog.filter.gradeOrders = selected
                                ? nil
                                : level.grade.sortOrder...level.grade.sortOrder
                        } label: {
                            VStack(spacing: 2) {
                                Text(level.grade.label).font(.headline)
                                Text("\(level.topped)/\(level.active)").font(.caption2.monospacedDigit())
                            }
                            .frame(minWidth: 44)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(.accentColor) : .regular, in: .capsule)
                    }
                }
            }
            Toggle("Tylko niezrobione", isOn: $catalog.filter.onlyNotTopped)
            if let lastVisit = catalog.lastVisit {
                Toggle("Nowe od ostatniej wizyty", isOn: Binding(
                    get: { catalog.filter.setAfter != nil },
                    set: { catalog.filter.setAfter = $0 ? lastVisit : nil }
                ))
            }
        }
    }
}

struct PinEditorTarget: Identifiable {
    let sectorId: UUID
    var id: UUID { sectorId }
}
