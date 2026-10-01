import BoulderKit
import SwiftUI

struct GymListView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            List(app.gyms) { gym in
                NavigationLink(value: gym) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gym.displayName).font(.headline)
                        if let address = gym.address {
                            Text(address).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if !gym.isPublished {
                            Label("Niewidoczna dla klientów", systemImage: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .overlay {
                if app.gyms.isEmpty {
                    ContentUnavailableView(
                        "Brak ścianek",
                        systemImage: "mountain.2",
                        description: Text("Twoja ścianka pojawi się tutaj, gdy zostanie opublikowana.")
                    )
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
