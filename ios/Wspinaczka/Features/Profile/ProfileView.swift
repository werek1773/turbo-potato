import BoulderKit
import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @State private var displayName = ""
    @State private var isAcceptingInvite = false
    @State private var isDeletingAccount = false
    @State private var exportURL: URL?
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some View {
        NavigationStack {
            Form {
                Section("Konto") {
                    TextField("Imię lub ksywka", text: $displayName)
                        .textContentType(.nickname)
                        .onSubmit { Task { await app.updateDisplayName(displayName) } }
                }

                Section("Wygląd") {
                    Picker("Motyw", selection: $appearance) {
                        ForEach(Appearance.allCases) { option in
                            Text(option.polishName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    ForEach(staffGyms, id: \.gym.id) { entry in
                        NavigationLink {
                            GymAdminView(gym: entry.gym)
                        } label: {
                            LabeledContent(entry.gym.displayName, value: entry.roleName)
                        }
                    }
                    Button("Mam kod zaproszenia", systemImage: "ticket") { isAcceptingInvite = true }
                } header: {
                    Text("Ścianki i role")
                } footer: {
                    Text("Kod zaproszenia dostajesz od managera ścianki.")
                }

                Section {
                    Toggle("Udział w anonimowych statystykach", isOn: Binding(
                        get: { !(app.profile?.statsOptOut ?? false) },
                        set: { value in Task { await app.setStatsOptOut(!value) } }
                    ))
                    Toggle("Zapisuj samopoczucie i ból", isOn: Binding(
                        get: { app.profile?.healthDataConsentAt != nil },
                        set: { value in Task { await app.setHealthDataConsent(value) } }
                    ))
                    Button("Pobierz moje dane", systemImage: "square.and.arrow.down") {
                        Task { await export() }
                    }
                    if let exportURL {
                        ShareLink("Udostępnij plik z danymi", item: exportURL)
                    }
                } header: {
                    Text("Prywatność")
                } footer: {
                    Text("Ścianka widzi tylko zbiorcze, anonimowe statystyki problemów (od 5 osób). Samopoczucie i ból są zawsze prywatne, a wyłączenie tej zgody usuwa zapisane wpisy.")
                }

                Section {
                    Button("Wyloguj") { Task { await app.signOut() } }
                    Button("Usuń konto", role: .destructive) { isDeletingAccount = true }
                }
            }
            .canvasBackground()
            .navigationTitle("Profil")
            .onAppear { displayName = app.profile?.displayName ?? "" }
            .onChange(of: app.profile?.displayName) { _, name in displayName = name ?? "" }
            .sheet(isPresented: $isAcceptingInvite) { AcceptInviteView() }
            .sheet(isPresented: $isDeletingAccount) { DeleteAccountView() }
        }
    }

    private var staffGyms: [(gym: Gym, roleName: String)] {
        app.gyms.compactMap { gym in
            if let role = app.access.role(in: gym.id) { return (gym, role.polishName) }
            if app.access.isPlatformAdmin { return (gym, "Admin") }
            return nil
        }
    }

    private func export() async {
        do {
            let data = try await app.backend.exportMyData()
            let url = FileManager.default.temporaryDirectory.appending(path: "wspinaczka-moje-dane.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            app.report(error)
        }
    }
}
