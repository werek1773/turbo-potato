#if DEBUG
import SwiftUI

/// Debug-only email + password sign-in, for the simulator where Sign in with
/// Apple needs an Apple Account. Not compiled into Release builds.
struct TestSignInView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var status: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-mail", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Hasło (min. 6 znaków)", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("Tylko w wersji Debug. Pierwszy raz użyj „Utwórz konto”, potem „Zaloguj”.")
                }
                Section {
                    Button("Zaloguj") { run(createAccount: false) }
                    Button("Utwórz konto") { run(createAccount: true) }
                }
                .disabled(isWorking || email.isEmpty || password.count < 6)
                if let status {
                    Section {
                        Text(status)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Logowanie testowe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
            }
        }
    }

    private func run(createAccount: Bool) {
        isWorking = true
        status = nil
        Task {
            defer { isWorking = false }
            do {
                let signedIn = try await app.backend.signInForTesting(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password,
                    createAccount: createAccount
                )
                if signedIn {
                    dismiss()
                } else {
                    status = "Konto utworzone. Potwierdź adres e-mail z wiadomości od Supabase, a potem się zaloguj."
                }
            } catch {
                status = UserFacingError.message(for: error)
            }
        }
    }
}
#endif
