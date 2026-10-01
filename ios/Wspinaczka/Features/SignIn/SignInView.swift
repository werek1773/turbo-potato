import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var app
    #if DEBUG
    @State private var isShowingTestSignIn = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                HoldMark(motion: .breathing)
                    .frame(width: 64)
                    .rise()
                Text("Wspinaj się.\nResztę zapiszemy.")
                    .font(.serif(.largeTitle))
                    .multilineTextAlignment(.center)
                    .rise(0.12)
                Text("Problemy Twojej ścianki na mapie, a sesja podsumowana po wyjściu.")
                    .font(.serif(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .rise(0.24)
            }
            Spacer()
            VStack(spacing: 14) {
                AppleSignInButton(label: .continue) { credential in
                    Task { await app.signIn(with: credential) }
                } onError: { error in
                    app.report(error)
                }
                .clipShape(Capsule())
                .rise(0.38)
                Text("Twoje przejścia i samopoczucie widzisz tylko Ty.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .rise(0.48)
                #if DEBUG
                Button("Logowanie testowe") { isShowingTestSignIn = true }
                    .font(.footnote)
                #endif
            }
        }
        .padding(24)
        .background(Palette.canvas.ignoresSafeArea())
        #if DEBUG
        .sheet(isPresented: $isShowingTestSignIn) {
            TestSignInView()
        }
        #endif
    }
}
