import BoulderKit
import SwiftUI

/// "Podsumuj sesję" for the gym and climbing day of a detected visit,
/// opened from the reminder notification or a `wspinaczka://session` link.
struct VisitSummarySheet: View {
    let route: SessionRoute

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let gym = app.gyms.first(where: { $0.id == route.gymId }) {
                    SessionDayView(gym: gym, day: route.day)
                        .navigationTitle(gym.name)
                } else if app.gyms.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "Nie ma tej ścianki",
                        systemImage: "mountain.2",
                        description: Text("Podsumuj sesję w zakładce Sesja.")
                    )
                }
            }
            .canvasBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
        }
    }
}
