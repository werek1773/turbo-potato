import BoulderKit
import SwiftUI

/// First run: introduce the app, ask for a name, explain privacy, pick a gym.
struct OnboardingView: View {
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case hello, rules, gym
    }

    @Environment(AppModel.self) private var app
    @AppStorage("favoriteGymId") private var favoriteGymId = ""
    @State private var step = Step.hello
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        ZStack {
            switch step {
            case .hello: hello
            case .rules: rules
            case .gym: gymChoice
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas.ignoresSafeArea())
        .animation(.smooth(duration: 0.5), value: step)
        .onAppear {
            let current = app.profile?.displayName ?? ""
            name = current == "Wspinacz" ? "" : current
        }
    }

    // MARK: Steps

    private var hello: some View {
        VStack(alignment: .leading, spacing: 14) {
            HoldMark(motion: .breathing)
                .frame(width: 44)
                .rise()
                .padding(.top, 24)
            RevealText("Cześć, jestem Wspinaczka.", delay: 0.2)
                .font(.serif(.largeTitle))
            RevealText("Pomogę Ci znaleźć problemy na ściance i zapamiętam, co już zrobiłeś.",
                       delay: 0.8, duration: 1.4)
                .font(.serif(.title3))
            VStack(alignment: .leading, spacing: 4) {
                Text("Mów do mnie…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Imię lub ksywka", text: $name)
                    .font(.title3)
                    .textContentType(.givenName)
                    .submitLabel(.continue)
                    .focused($isNameFocused)
                    .onSubmit(saveName)
            }
            .paperCard()
            .rise(1.9)
            .padding(.top, 8)
            Spacer()
            Button("Dalej", action: saveName)
                .buttonStyle(.pill)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .rise(2.1)
            Text("Imię zmienisz później w profilu.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .rise(2.2)
        }
        .transition(.blurReplace)
        .task {
            try? await Task.sleep(for: .seconds(2.2))
            if name.isEmpty { isNameFocused = true }
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 22) {
            RevealText("Trzy rzeczy na start", delay: 0.1)
                .font(.serif(.largeTitle))
                .padding(.top, 48)
            RuleRow(symbol: "iphone.slash", colors: [Palette.coral, Palette.olive], delay: 0.5,
                    title: "Telefon zostaje w torbie.",
                    detail: "Przejścia zaznaczasz po sesji, kilkoma dotknięciami w pinezki.")
            RuleRow(symbol: "lock.fill", colors: [Palette.chartreuse, Palette.olive], delay: 0.75,
                    title: "Twoje dane są prywatne.",
                    detail: "Przejścia, to co Cię zatrzymało i samopoczucie widzisz tylko Ty.")
            RuleRow(symbol: "chart.bar.fill", colors: [Palette.mustard, Palette.olive], delay: 1.0,
                    title: "Ścianka widzi tylko sumy.",
                    detail: "Na przykład ilu osobom wyszedł problem. Nigdy kto.")
            Spacer()
            Button("Rozumiem") { step = .gym }
                .buttonStyle(.pill)
                .rise(1.2)
        }
        .transition(.blurReplace)
    }

    private var gymChoice: some View {
        VStack(alignment: .leading, spacing: 18) {
            RevealText("Gdzie się wspinasz?", delay: 0.1)
                .font(.serif(.largeTitle))
                .padding(.top, 48)
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(app.gyms.enumerated()), id: \.element.id) { index, gym in
                        Button {
                            favoriteGymId = gym.id.uuidString
                            onFinish()
                        } label: {
                            GymCard(gym: gym)
                        }
                        .buttonStyle(.plain)
                        .rise(0.35 + Double(index) * 0.12)
                    }
                    if app.gyms.isEmpty {
                        Text("Twoja ścianka pojawi się tu, gdy dołączy do aplikacji.")
                            .foregroundStyle(.secondary)
                            .rise(0.35)
                    }
                }
            }
            .scrollClipDisabled()
            Button("Pomiń", action: onFinish)
                .buttonStyle(.pillSecondary)
                .rise(0.6)
        }
        .transition(.blurReplace)
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isNameFocused = false
        if trimmed != app.profile?.displayName {
            Task { await app.updateDisplayName(trimmed) }
        }
        step = .rules
    }
}

private struct RuleRow: View {
    let symbol: String
    let colors: [Color]
    let delay: Double
    let title: String
    let detail: String

    @State private var bounce = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(colors[0], colors[1])
                .font(.system(size: 26))
                .frame(width: 36)
                .symbolEffect(.bounce, value: bounce)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .rise(delay)
        .task {
            try? await Task.sleep(for: .seconds(delay + 0.3))
            bounce.toggle()
        }
    }
}

/// A gym on a card: its plan drawing itself in, name and address.
struct GymCard: View {
    let gym: Gym

    @State private var paths: [[MapPoint]] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan = gym.floorPlan {
                MiniMapView(plan: plan, paths: paths)
                    .frame(maxHeight: 170)
                    .frame(maxWidth: .infinity)
                    .id(paths.count)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(gym.displayName)
                    .font(.serif(.title2))
                    .foregroundStyle(Palette.ink)
                if let address = gym.address {
                    Text(address).font(.subheadline).foregroundStyle(.secondary)
                }
                if !gym.isPublished {
                    Label("Niewidoczna dla klientów", systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(Palette.mustard)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(radius: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .task(id: gym.id) {
            guard gym.floorPlan != nil, paths.isEmpty else { return }
            paths = (try? await Backend.shared.sectors(gymId: gym.id))?.compactMap(\.mapPath) ?? []
        }
    }
}
