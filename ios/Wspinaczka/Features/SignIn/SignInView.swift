import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var app
    #if DEBUG
    @State private var isShowingTestSignIn = false
    #endif

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Wspinaczka")
                    .font(.largeTitle.bold())
                Text("Problemy Twojej ścianki, podsumowanie sesji w minutę i postępy, które widać.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            AppleSignInButton { credential in
                Task { await app.signIn(with: credential) }
            } onError: { error in
                app.report(error)
            }
            Text("Logując się, akceptujesz zasady prywatności. Twoje przejścia i samopoczucie widzisz tylko Ty.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            #if DEBUG
            Button("Logowanie testowe") { isShowingTestSignIn = true }
                .font(.footnote)
            #endif
        }
        .padding(24)
        #if DEBUG
        .sheet(isPresented: $isShowingTestSignIn) {
            TestSignInView()
        }
        #endif
    }
}
