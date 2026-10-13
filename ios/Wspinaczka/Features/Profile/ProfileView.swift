import BoulderKit
import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(VisitMonitor.self) private var visits
    @State private var isEditingName = false
    @State private var draftName = ""
    @State private var isAcceptingInvite = false
    @State private var isDeletingAccount = false
    @State private var isSigningOut = false
    @State private var exportURL: URL?
    @State private var stats: ClimberStatsModel?
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let stats, stats.hasLoaded, !stats.isEmpty {
                        MiniStats(stats: stats)
                    }
                    gymsSection
                    appearanceSection
                    remindersAndPrivacy
                    accountActions
                }
                .padding()
            }
            .canvasBackground()
            .navigationTitle("Profil")
            // The header is the title; nothing else lives in the bar.
            .toolbarVisibility(.hidden, for: .navigationBar)
            .alert("Imię lub ksywka", isPresented: $isEditingName) {
                TextField("Imię lub ksywka", text: $draftName)
                    .textContentType(.nickname)
                Button("Zapisz") { Task { await app.updateDisplayName(draftName) } }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("Tak zobaczą Cię osoby z Twojej ścianki.")
            }
            .confirmationDialog("Wylogować się?", isPresented: $isSigningOut, titleVisibility: .visible) {
                Button("Wyloguj") { Task { await app.signOut() } }
            }
            .sheet(isPresented: $isAcceptingInvite) { AcceptInviteView() }
            .sheet(isPresented: $isDeletingAccount) { DeleteAccountView() }
            .task(id: app.gyms.first?.id) { await loadStats() }
        }
    }

    // MARK: Header

    private var displayName: String {
        let name = app.profile?.displayName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Wspinacz" : name
    }

    private var initials: String {
        let words = (app.profile?.displayName ?? "").split(separator: " ").prefix(2)
        return words.compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    private var subtitle: String {
        if let entry = staffGyms.first { return "\(entry.gym.name) · \(entry.roleName.lowercased())" }
        return app.gyms.first?.name ?? "Wspinaczka"
    }

    private var header: some View {
        Button {
            draftName = app.profile?.displayName ?? ""
            isEditingName = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Palette.mat)
                    Circle().stroke(Palette.moss, lineWidth: 2)
                    if initials.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundStyle(Palette.mossDark)
                    } else {
                        Text(initials)
                            .font(.display(.title2))
                            .foregroundStyle(Palette.mossDark)
                    }
                }
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.display(.title))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "pencil")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(displayName), \(subtitle)")
        .accessibilityHint("Zmień imię lub ksywkę")
    }

    // MARK: Gyms

    private var staffGyms: [(gym: Gym, roleName: String)] {
        app.gyms.compactMap { gym in
            if let role = app.access.role(in: gym.id) { return (gym, role.polishName) }
            if app.access.isPlatformAdmin { return (gym, "Admin") }
            return nil
        }
    }

    private var gymsSection: some View {
        ProfileGroup(title: "Twoje ścianki", footer: "Kod zaproszenia dostajesz od managera ścianki.") {
            ForEach(staffGyms, id: \.gym.id) { entry in
                NavigationLink {
                    GymAdminView(gym: entry.gym)
                } label: {
                    ProfileRow {
                        Capsule().fill(Palette.moss).frame(width: 6, height: 24)
                        Text(entry.gym.displayName).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(entry.roleName.lowercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.mossDark)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Palette.mat, in: Capsule())
                        Chevron()
                    }
                }
                .buttonStyle(.plain)
                RowDivider()
            }
            Button { isAcceptingInvite = true } label: {
                ProfileRow {
                    Image(systemName: "ticket").foregroundStyle(Palette.mossDark)
                    Text("Mam kod zaproszenia").foregroundStyle(Palette.mossDark)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupTitle("Wygląd")
            HStack(spacing: 10) {
                ForEach(Appearance.allCases) { option in
                    AppearanceSwatch(option: option, isOn: appearance == option) {
                        withAnimation(.snappy) { appearance = option }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: appearance)
    }

    // MARK: Reminders and privacy

    private var reminderStatus: String {
        guard visits.state.isEnabled else { return "wyłączone" }
        return visits.status.isWorking ? "włączone" : "wymaga uwagi"
    }

    private var remindersAndPrivacy: some View {
        ProfileGroup(
            title: "Przypomnienia i prywatność",
            footer: "Ścianka widzi tylko zbiorcze, anonimowe statystyki problemów (od 5 osób). Samopoczucie i ból zostają u Ciebie, a wyłączenie tej zgody usuwa zapisane wpisy."
        ) {
            NavigationLink {
                VisitSettingsView()
            } label: {
                ProfileRow {
                    Text("Przypomnij po wizycie").foregroundStyle(Palette.ink)
                    Spacer()
                    Text(reminderStatus)
                        .font(.subheadline)
                        .foregroundStyle(visits.state.isEnabled && !visits.status.isWorking
                                         ? Palette.mustardText : Palette.muted)
                    Chevron()
                }
            }
            .buttonStyle(.plain)
            RowDivider()
            ProfileRow {
                Toggle("Anonimowe statystyki", isOn: Binding(
                    get: { !(app.profile?.statsOptOut ?? false) },
                    set: { value in Task { await app.setStatsOptOut(!value) } }
                ))
                .foregroundStyle(Palette.ink)
            }
            RowDivider()
            ProfileRow {
                Toggle("Samopoczucie i ból", isOn: Binding(
                    get: { app.profile?.healthDataConsentAt != nil },
                    set: { value in Task { await app.setHealthDataConsent(value) } }
                ))
                .foregroundStyle(Palette.ink)
            }
            RowDivider()
            if let exportURL {
                ShareLink(item: exportURL) {
                    ProfileRow {
                        Image(systemName: "square.and.arrow.up").foregroundStyle(Palette.mossDark)
                        Text("Udostępnij plik z danymi").foregroundStyle(Palette.mossDark)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button { Task { await export() } } label: {
                    ProfileRow {
                        Image(systemName: "square.and.arrow.down").foregroundStyle(Palette.mossDark)
                        Text("Pobierz moje dane").foregroundStyle(Palette.mossDark)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .tint(Palette.moss)
    }

    // MARK: Account

    private var accountActions: some View {
        VStack(spacing: 4) {
            Button("Wyloguj") { isSigningOut = true }
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
            Button("Usuń konto") { isDeletingAccount = true }
                .foregroundStyle(Palette.coral)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .font(.body.weight(.medium))
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: Actions

    private func loadStats() async {
        guard let gym = app.gyms.first else { stats = nil; return }
        let model = ClimberStatsModel(gym: gym)
        stats = model
        try? await model.load()
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

// MARK: - Pieces

/// Three numbers under the name: days climbed, hardest top, week streak.
private struct MiniStats: View {
    let stats: ClimberStatsModel

    var body: some View {
        let overview = stats.overview
        HStack(spacing: 10) {
            Tile(value: "\(overview.climbingDays)", caption: sessionsWord(overview.climbingDays))
            Tile(value: overview.hardestTop?.label ?? "—", caption: "najtrudniejszy")
            Tile(value: "\(stats.weekStreak) tyg.", caption: "seria")
        }
    }

    private func sessionsWord(_ count: Int) -> String {
        switch PolishPlural(count) {
        case .one: "sesja"
        case .few: "sesje"
        case .many: "sesji"
        }
    }

    private struct Tile: View {
        let value: String
        let caption: String

        var body: some View {
            VStack(spacing: 2) {
                Text(value)
                    .font(.display(.title3).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .paperCard(padding: 12, radius: 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(caption): \(value)")
        }
    }
}

/// A small title, a paper card of rows, and an optional note under it.
private struct ProfileGroup<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupTitle(title)
            VStack(spacing: 0) { content }
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.line))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GroupTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct ProfileRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 14)
    }
}

private struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.muted)
    }
}

/// A tiny picture of the theme: half and half for "Systemowy".
private struct AppearanceSwatch: View {
    let option: Appearance
    let isOn: Bool
    let action: () -> Void

    private static let day = Color(hex: 0xF7F5EE)
    private static let night = Color(hex: 0x191A15)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Palette.line))
                Text(option.polishName)
                    .font(.footnote.weight(isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Palette.mossDark : Palette.ink)
            }
            .padding(7)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isOn ? Palette.moss : Palette.line, lineWidth: isOn ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Motyw: \(option.polishName)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private var preview: some View {
        switch option {
        case .system:
            HStack(spacing: 0) { Self.day; Self.night }
        case .light:
            Self.day.overlay(alignment: .bottomLeading) { swatchLine(Color(hex: 0x6B8131)) }
        case .dark:
            Self.night.overlay(alignment: .bottomLeading) { swatchLine(Color(hex: 0x7F9839)) }
        }
    }

    private func swatchLine(_ color: Color) -> some View {
        Capsule().fill(color).frame(width: 22, height: 5).padding(7)
    }
}
