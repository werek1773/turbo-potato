import BoulderKit
import SwiftUI

struct AcceptInviteView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var outcome: String?
    @State private var isWorking = false

    init(initialCode: String = "") {
        _code = State(initialValue: initialCode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("XXXX-XXXX-XXXX", text: $code)
                        .font(.title3.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    if let outcome { Text(outcome) }
                }
                Button("Dołącz") { Task { await accept() } }
                    .disabled(!InviteCode.isComplete(code) || isWorking)
            }
            .navigationTitle("Kod zaproszenia")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
        }
    }

    private func accept() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await app.backend.acceptInvite(code: code)
            switch result.status {
            case .ok:
                await app.refresh()
                let gymName = app.gyms.first { $0.id == result.gymId }?.name ?? "ścianki"
                outcome = "Gotowe! Masz rolę \(result.role?.polishName ?? "") w \(gymName)."
            case .invalid:
                outcome = "Ten kod jest nieprawidłowy, wygasł albo został już wykorzystany."
            case .rateLimited:
                outcome = "Zbyt wiele prób. Spróbuj ponownie za godzinę."
            }
        } catch {
            app.report(error)
        }
    }
}

/// Manager tools for one gym: invites and publishing.
struct GymAdminView: View {
    @Environment(AppModel.self) private var app
    let gym: Gym
    @State private var invite: CreatedInvite?
    @State private var invitedRole: GymRole = .routesetter
    @State private var isPublished: Bool

    init(gym: Gym) {
        self.gym = gym
        _isPublished = State(initialValue: gym.isPublished)
    }

    var body: some View {
        Form {
            if app.access.isManager(of: gym.id) {
                Section {
                    Toggle("Ścianka widoczna dla klientów", isOn: $isPublished)
                        .onChange(of: isPublished) { _, value in
                            Task {
                                do {
                                    try await app.backend.setGymPublished(gymId: gym.id, published: value)
                                    await app.refresh()
                                } catch {
                                    app.report(error)
                                }
                            }
                        }
                } footer: {
                    Text("Opublikuj, gdy sektory i problemy są gotowe.")
                }

                Section {
                    Button("Zaproś routesettera", systemImage: "person.badge.plus") {
                        Task { await createInvite(.routesetter) }
                    }
                    if app.access.isPlatformAdmin {
                        Button("Zaproś managera", systemImage: "person.badge.key") {
                            Task { await createInvite(.manager) }
                        }
                    }
                    if let invite {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(invite.code)
                                .font(.title2.monospaced().bold())
                                .textSelection(.enabled)
                            Text("\(invitedRole.polishName) · ważny do \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened)) · jednorazowy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ShareLink(
                            "Wyślij zaproszenie",
                            item: InviteCode.url(for: invite.code),
                            message: Text("Zaproszenie do \(gym.name) w aplikacji Wspinaczka. Kod: \(invite.code)")
                        )
                    }
                } header: {
                    Text("Zaproszenia")
                }
            }
        }
        .navigationTitle(gym.name)
    }

    private func createInvite(_ role: GymRole) async {
        do {
            invite = try await app.backend.createInvite(gymId: gym.id, role: role)
            invitedRole = role
        } catch {
            app.report(error)
        }
    }
}
