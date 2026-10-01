import SwiftUI

/// Signing in again after signing out; the first launch goes through the intro.
struct SignInView: View {
    @Environment(AppModel.self) private var app
    #if DEBUG
    @State private var isShowingTestSignIn = false
    #endif

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            DrawingView(drawing: .grip)
                .frame(height: 200)
            Text("Wspinaczka")
                .font(.display(.largeTitle))
                .foregroundStyle(Palette.ink)
            Text("Problemy Twojej ścianki na mapie i sesja zapisana po wyjściu.")
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Spacer()
            AppleSignInButton(label: .continue) { credential in
                Task { await app.signIn(with: credential) }
            } onError: { error in
                app.report(error)
            }
            .clipShape(Capsule())
            Text("Twoje przejścia widzisz tylko Ty.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            #if DEBUG
            Button("Logowanie testowe") { isShowingTestSignIn = true }
                .font(.footnote)
            #endif
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
