import BoulderKit
import SwiftUI

@main
struct WspinaczkaApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
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

    var body: some View {
        @Bindable var app = app
        Group {
            switch app.phase {
            case .launching:
                ProgressView()
            case .signedOut:
                SignInView()
            case .signedIn:
                MainTabView()
            }
        }
        .alert("Coś poszło nie tak", isPresented: $app.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
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
                SessionPlaceholderView()
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
