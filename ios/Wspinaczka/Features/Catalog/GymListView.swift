import BoulderKit
import SwiftUI

/// Gyms as cards with their plans; shown only when there is more than one.
struct GymListView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                if app.gyms.isEmpty {
                    ChalkEmptyState(
                        title: "Brak ścianek",
                        message: "Twoja ścianka pojawi się tutaj, gdy zostanie opublikowana.",
                        refresh: { await app.refresh() }
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(app.gyms) { gym in
                                NavigationLink(value: gym) {
                                    GymCard(gym: gym)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    .canvasBackground()
                    .refreshable { await app.refresh() }
                }
            }
            .navigationTitle("Ścianki")
            .navigationDestination(for: Gym.self) { gym in
                GymView(gym: gym)
            }
        }
    }
}

/// A gym on a card: its plan, name and address.
struct GymCard: View {
    let gym: Gym

    @State private var paths: [[MapPoint]] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan = gym.floorPlan {
                MiniMapView(plan: plan, paths: paths)
                    .frame(maxHeight: 170)
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(gym.displayName)
                    .font(.display(.title3))
                    .foregroundStyle(Palette.ink)
                if let address = gym.address {
                    Text(address).font(.subheadline).foregroundStyle(Palette.muted)
                }
                if !gym.isPublished {
                    Label("Niewidoczna dla klientów", systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(Palette.mustardText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(radius: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .task(id: gym.id) {
            guard gym.floorPlan != nil, paths.isEmpty else { return }
            paths = (try? await Backend.shared.sectors(gymId: gym.id))?.compactMap(\.mapPath) ?? []
        }
    }
}
