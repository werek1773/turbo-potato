import SwiftUI

struct SessionPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Podsumuj sesję",
                systemImage: "checklist",
                description: Text("Tu po wyjściu ze ścianki zaznaczysz, co zrobiłeś, w mniej niż minutę. Ten ekran powstaje w następnym kroku.")
            )
            .navigationTitle("Sesja")
        }
    }
}
