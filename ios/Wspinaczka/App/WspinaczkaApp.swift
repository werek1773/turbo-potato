import BoulderKit
import SwiftUI

@main
struct WspinaczkaApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Palette.olive)
                .task { app.start() }
                .onOpenURL { url in
                    if let code = InviteCode.code(from: url) {
                        app.pendingInvite = PendingInvite(code: code)
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    /// The mark gets to finish drawing itself even when the session is restored instantly.
    @State private var isSplashDone = false

    var body: some View {
        @Bindable var app = app
        ZStack {
            if !isSplashDone || app.phase == .launching {
                SplashView()
                    .transition(.opacity)
            } else if case let .signedIn(userId) = app.phase {
                SignedInRoot(userId: userId)
                    .id(userId)
                    .transition(.blurReplace)
            } else {
                SignInView()
                    .transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.6), value: app.phase)
        .animation(.smooth(duration: 0.6), value: isSplashDone)
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            isSplashDone = true
        }
        .alert("Coś poszło nie tak", isPresented: $app.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}

/// First run after signing in goes through onboarding, then the tabs.
struct SignedInRoot: View {
    @AppStorage private var isOnboarded: Bool

    init(userId: UUID) {
        _isOnboarded = AppStorage(wrappedValue: false, "onboarded.\(userId.uuidString)")
    }

    var body: some View {
        ZStack {
            if isOnboarded {
                MainTabView()
                    .transition(.blurReplace)
            } else {
                OnboardingView { isOnboarded = true }
                    .transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.6), value: isOnboarded)
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 12) {
                HoldMark(motion: .drawIn)
                    .frame(width: 52)
                Text("Wspinaczka")
                    .font(.serif(.largeTitle))
                    .rise(0.9)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Palette.canvas.ignoresSafeArea())
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView {
            Tab("Ścianki", systemImage: "mountain.2") {
                GymListView()
            }
            Tab("Sesja", systemImage: "checklist") {
                SessionView()
            }
            Tab("Profil", systemImage: "person.crop.circle") {
                ProfileView()
            }
        }
        .sheet(item: $app.pendingInvite) { invite in
            AcceptInviteView(initialCode: invite.code)
        }
    }
}
