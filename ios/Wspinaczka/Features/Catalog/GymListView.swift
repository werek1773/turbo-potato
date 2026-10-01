import BoulderKit
import SwiftUI

/// Gyms as cards with their plans; shown only when there is more than one.
struct GymListView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(app.gyms) { gym in
                        NavigationLink(value: gym) {
                            GymCard(gym: gym)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .canvasBackground()
            .overlay {
                if app.gyms.isEmpty {
                    VStack(spacing: 8) {
                        DrawingView(drawing: .chalk)
                            .frame(height: 140)
                        Text("Brak ścianek")
                            .font(.display(.title3))
                        Text("Twoja ścianka pojawi się tutaj, gdy zostanie opublikowana.")
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                }
            }
            .navigationTitle("Ścianki")
            .navigationDestination(for: Gym.self) { gym in
                GymView(gym: gym)
            }
            .refreshable { await app.refresh() }
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
