import BoulderKit
import SwiftUI

/// Energy, effort, skin and pain of the session. Health data: stored only
/// after an explicit opt-in and never shared with the gym.
struct WellbeingSection: View {
    let log: SessionLog

    @Environment(AppModel.self) private var app
    @State private var energy: Int?
    @State private var rpe: Int?
    @State private var skin: SkinState?
    @State private var pain: Set<BodyArea> = []
    @State private var isSaving = false
    @State private var savedSnapshot: SessionWellbeing?

    private var hasConsent: Bool { app.profile?.healthDataConsentAt != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Samopoczucie").font(.title2.bold())

            if hasConsent {
                form
            } else {
                Text("Zapisuj energię, zmęczenie, stan skóry i ból po sesji, żeby widzieć, kiedy odpuścić. Te dane widzisz tylko Ty — ścianka nigdy ich nie dostaje. Możesz to wyłączyć w Profilu, wtedy wpisy zostaną usunięte.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Włącz zapisywanie samopoczucia") {
                    Task { await app.setHealthDataConsent(true) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onAppear { syncFromLog() }
        .onChange(of: log.wellbeing) { _, _ in syncFromLog() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Energia").font(.subheadline.weight(.semibold))
                Picker("Energia", selection: $energy) {
                    Text("—").tag(Int?.none)
                    ForEach(1...5, id: \.self) { Text("\($0)").tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Jak ciężka była sesja (RPE \(rpe.map { "\($0)" } ?? "—")/10)")
                    .font(.subheadline.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { Double(rpe ?? 5) },
                        set: { rpe = Int($0.rounded()) }
                    ),
                    in: 1...10,
                    step: 1
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Skóra").font(.subheadline.weight(.semibold))
                Picker("Skóra", selection: $skin) {
                    Text("—").tag(SkinState?.none)
                    ForEach(SkinState.allCases, id: \.self) { Text($0.polishName).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Coś boli?").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(BodyArea.allCases, id: \.self) { area in
                        let selected = pain.contains(area)
                        Button {
                            if selected { pain.remove(area) } else { pain.insert(area) }
                        } label: {
                            Text(area.polishName)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(selected ? Color.red.opacity(0.2) : Color.secondary.opacity(0.1),
                                            in: Capsule())
                                .overlay(Capsule().stroke(selected ? Color.red : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }

            HStack {
                Spacer()
                if isSaving {
                    ProgressView()
                } else {
                    Button("Zapisz samopoczucie") { Task { await save() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(energy == nil && rpe == nil && skin == nil && pain.isEmpty)
                }
            }
        }
    }

    private func syncFromLog() {
        guard log.wellbeing != savedSnapshot else { return }
        savedSnapshot = log.wellbeing
        energy = log.wellbeing?.energy
        rpe = log.wellbeing?.rpe
        skin = log.wellbeing?.skin
        pain = Set(log.wellbeing?.painAreas ?? [])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await log.saveWellbeing(energy: energy, rpe: rpe, skin: skin, painAreas: pain)
        } catch {
            app.report(error)
        }
    }
}
