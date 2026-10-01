import BoulderKit
import SwiftUI

/// Home: a greeting and the gyms as cards with their plans.
struct GymListView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("favoriteGymId") private var favoriteGymId = ""

    /// The gym picked during onboarding comes first.
    private var gyms: [Gym] {
        app.gyms.sorted { lhs, rhs in
            (lhs.id.uuidString == favoriteGymId ? 0 : 1) < (rhs.id.uuidString == favoriteGymId ? 0 : 1)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HoldMark(motion: .breathing)
                            .frame(width: 40)
                        Text(Greeting.text(for: app.profile?.displayName))
                            .font(.serif(.largeTitle))
                            .contentTransition(.opacity)
                    }
                    .padding(.top, 8)
                    .rise()

                    ForEach(Array(gyms.enumerated()), id: \.element.id) { index, gym in
                        NavigationLink(value: gym) {
                            GymCard(gym: gym)
                        }
                        .buttonStyle(.plain)
                        .rise(0.15 + Double(index) * 0.1)
                    }
                }
                .padding()
            }
            .canvasBackground()
            .overlay {
                if app.gyms.isEmpty {
                    ContentUnavailableView(
                        "Brak ścianek",
                        systemImage: "mountain.2",
                        description: Text("Twoja ścianka pojawi się tutaj, gdy zostanie opublikowana.")
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Gym.self) { gym in
                GymView(gym: gym)
            }
            .refreshable { await app.refresh() }
        }
    }
}
