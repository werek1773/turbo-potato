import BoulderKit
import SwiftUI

@main
struct WspinaczkaApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Palette.moss)
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
    @AppStorage("hasSeenIntro") private var hasSeenIntro = false
    @AppStorage("appearance") private var appearance = Appearance.system
    /// The splash gets to finish even when the session is restored instantly.
    @State private var isSplashDone = false
    /// Decided once per launch: the whole climb on the very first launch only.
    @State private var isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasSeenIntro")

    var body: some View {
        @Bindable var app = app
        ZStack {
            if !isSplashDone || app.phase == .launching {
                SplashView(isFirstLaunch: isFirstLaunch)
                    .transition(.opacity)
            } else if case .signedIn = app.phase {
                MainTabView()
                    .transition(.opacity)
            } else if hasSeenIntro {
                SignInView()
                    .transition(.opacity)
            } else {
                IntroView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.5), value: app.phase)
        .animation(.smooth(duration: 0.5), value: isSplashDone)
        .preferredColorScheme(appearance.colorScheme)
        .task {
            // The hand draws itself in 13 frames; give the name a moment after it.
            let duration = isFirstLaunch ? Double(Drawing.grip.drawOnFrames) / StopMotion.fps + 0.9 : 0.8
            try? await Task.sleep(for: .seconds(duration))
            isSplashDone = true
        }
        .alert("Coś poszło nie tak", isPresented: $app.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}

/// On the first launch the hand draws itself onto the hold; later it is
/// already there.
struct SplashView: View {
    let isFirstLaunch: Bool

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            DrawingView(drawing: .grip, drawsOn: isFirstLaunch)
                .frame(height: 220)
            Text("Wspinaczka")
                .font(.display(.largeTitle))
                .foregroundStyle(Palette.ink)
                .padding(.top, 12)
                .fadeUp(isFirstLaunch ? Double(Drawing.grip.drawOnFrames) / StopMotion.fps - 0.2 : 0)
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
            Tab("Ścianka", systemImage: "map") {
                GymsTab()
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

/// With one gym (the usual case) its map opens straight away.
struct GymsTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.gyms.count == 1, let gym = app.gyms.first {
            NavigationStack {
                GymView(gym: gym)
            }
            .id(gym.id)
        } else {
            GymListView()
        }
    }
}
