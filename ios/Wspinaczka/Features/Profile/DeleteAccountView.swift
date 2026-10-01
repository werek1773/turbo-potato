import SwiftUI

/// Apple requires in-app account deletion. Re-authenticating with Apple gives
/// the server a fresh code to revoke the Sign in with Apple tokens.
struct DeleteAccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Usunięcie konta jest nieodwracalne.")
                    .font(.title3.bold())
                Text("Skasujemy Twój profil, wszystkie sesje, przejścia i samopoczucie. Problemy, które ustawiłeś jako routesetter, zostaną na ściance bez Twojego nazwiska.")
                    .foregroundStyle(.secondary)
                Spacer()
                if isDeleting {
                    ProgressView("Usuwanie konta…")
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Potwierdź tożsamość przez Apple, aby usunąć konto:")
                        .font(.footnote)
                    AppleSignInButton(label: .continue) { credential in
                        isDeleting = true
                        Task {
                            let deleted = await app.deleteAccount(confirmedWith: credential)
                            isDeleting = false
                            if deleted { dismiss() }
                        }
                    } onError: { error in
                        app.report(error)
                    }
                }
            }
            .padding(24)
            .navigationTitle("Usuń konto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
            }
        }
    }
}
