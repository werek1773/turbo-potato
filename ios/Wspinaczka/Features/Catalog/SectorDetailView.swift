import BoulderKit
import SwiftUI

/// One sector: its photo with pins, what is announced, and the staff tools.
struct SectorDetailView: View {
    let catalog: GymCatalog
    let sectorId: UUID

    @Environment(AppModel.self) private var app
    @State private var isPlanningReset = false
    @State private var isTakingPhoto = false
    @State private var pinEditor: PinEditorTarget?
    @State private var editorAfterPhoto = false

    private var sector: Sector? { catalog.sectors.first { $0.id == sectorId } }
    private var isStaff: Bool { app.access.isStaff(of: catalog.gym.id) }

    var body: some View {
        ScrollView {
            if let sector {
                VStack(alignment: .leading, spacing: 16) {
                    if let reset = catalog.upcomingReset(for: sector) {
                        ResetBadge(reset: reset)
                    }
                    if let photo = catalog.photo(of: sector) {
                        SectorPhotoView(
                            photo: photo,
                            problems: catalog.problems(in: sector),
                            highlighted: catalog.visibleProblemIds,
                            topped: catalog.toppedProblemIds,
                            gradeLabels: catalog.gradesById.mapValues(\.label)
                        )
                        problemSummary(sector)
                    } else {
                        VStack(spacing: 8) {
                            DrawingView(drawing: .chalk)
                                .frame(height: 150)
                            Text("Brak zdjęcia sektora")
                                .font(.display(.title3))
                            Text(isStaff
                                 ? "Zrób zdjęcie ściany i zaznacz na nim problemy."
                                 : "Routesetterzy jeszcze nie dodali tego sektora.")
                                .foregroundStyle(Palette.muted)
                                .multilineTextAlignment(.center)
                            if isStaff {
                                Button("Zrób zdjęcie sektora") { isTakingPhoto = true }
                                    .buttonStyle(.pill)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                    if let lastReset = sector.lastResetAt {
                        Text("Ostatnia przykrętka: \(lastReset.formatted(date: .long, time: .omitted))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .canvasBackground()
        .navigationTitle(sector?.name ?? "")
        .toolbar {
            if isStaff, let sector {
                Menu {
                    Button(catalog.photo(of: sector) == nil ? "Dodaj zdjęcie sektora" : "Przykrętka / nowe zdjęcie",
                           systemImage: "camera") { isTakingPhoto = true }
                    if catalog.photo(of: sector) != nil {
                        Button("Problemy i pinezki", systemImage: "mappin.and.ellipse") {
                            pinEditor = PinEditorTarget(sectorId: sector.id)
                        }
                    }
                    Button("Data następnej przykrętki", systemImage: "calendar.badge.clock") {
                        isPlanningReset = true
                    }
                } label: {
                    Label("Opcje sektora", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isTakingPhoto, onDismiss: {
            if editorAfterPhoto {
                editorAfterPhoto = false
                pinEditor = PinEditorTarget(sectorId: sectorId)
            }
        }) {
            if let sector {
                NewSectorPhotoView(catalog: catalog, sector: sector) { editorAfterPhoto = true }
            }
        }
        .sheet(isPresented: $isPlanningReset) {
            if let sector {
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
        }
        .fullScreenCover(item: $pinEditor) { target in
            PinEditorView(catalog: catalog, sectorId: target.sectorId)
        }
        .refreshable {
            do { try await catalog.load() } catch { app.report(error) }
        }
    }

    private func problemSummary(_ sector: Sector) -> some View {
        let problems = catalog.problems(in: sector)
        let topped = catalog.toppedCount(in: sector)
        return HStack {
            Label("\(problems.count) problemów", systemImage: "mappin")
            Spacer()
            Label("zrobione \(topped)/\(problems.count)", systemImage: "checkmark.circle")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
