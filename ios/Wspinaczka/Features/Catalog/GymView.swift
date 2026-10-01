import BoulderKit
import SwiftUI

struct GymView: View {
    @Environment(AppModel.self) private var app
    @State private var catalog: GymCatalog
    @State private var isAddingSector = false
    @State private var newSectorName = ""

    init(gym: Gym) {
        _catalog = State(initialValue: GymCatalog(gym: gym, backend: Backend.shared))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !catalog.coverage.isEmpty {
                    GradeFilterBar(catalog: catalog)
                }
                ForEach(catalog.sectors) { sector in
                    SectorCard(
                        sector: sector,
                        photo: sector.currentPhotoId.flatMap { catalog.photos[$0] },
                        problems: catalog.problems(in: sector),
                        highlighted: catalog.visibleProblemIds,
                        topped: catalog.toppedProblemIds
                    )
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
                Button("Dodaj sektor", systemImage: "plus") { isAddingSector = true }
            }
        }
        .alert("Nowy sektor", isPresented: $isAddingSector) {
            TextField("Nazwa, np. Grota", text: $newSectorName)
            Button("Dodaj") {
                let name = newSectorName
                newSectorName = ""
                Task {
                    do { try await catalog.addSector(named: name) } catch { app.report(error) }
                }
            }
            Button("Anuluj", role: .cancel) { newSectorName = "" }
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
