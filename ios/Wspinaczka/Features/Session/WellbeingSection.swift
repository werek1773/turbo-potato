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
    @State private var savedSnapshot: WellbeingValues?

    private var hasConsent: Bool { app.profile?.healthDataConsentAt != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Jak się czujesz?")
                    .font(.display(.title3))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Label("prywatne", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }

            if hasConsent {
                form
            } else {
                Text("Zapisuj energię, zmęczenie, skórę i ból po sesji, żeby widzieć, kiedy odpuścić. Widzisz je tylko Ty, ścianka nigdy ich nie dostaje. Wyłączenie w Profilu usuwa wpisy.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Włącz samopoczucie") {
                    Task { await app.setHealthDataConsent(true) }
                }
                .buttonStyle(.pillSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(radius: 18)
        .onAppear { syncFromLog() }
        .onChange(of: log.wellbeing) { _, _ in syncFromLog() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Field(title: "Energia", value: energy.map { "\($0)/5" }) {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            energy = energy == level ? nil : level
                        } label: {
                            Circle()
                                .fill(level <= (energy ?? 0) ? Palette.mossLight : Palette.mat)
                                .overlay(Circle().stroke(level == energy ? Palette.moss : .clear, lineWidth: 2))
                                .frame(width: 30, height: 30)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Energia \(level) z 5")
                        .accessibilityAddTraits(level == energy ? .isSelected : [])
                    }
                }
            }

            Field(title: "Jak ciężka była sesja", value: rpe.map { "RPE \($0)/10" }) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(1...10, id: \.self) { value in
                        let isOn = value == rpe
                        Button {
                            rpe = isOn ? nil : value
                        } label: {
                            Text("\(value)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(isOn ? Palette.paper : Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(isOn ? Palette.moss : Palette.canvas, in: Capsule())
                                .overlay(Capsule().stroke(isOn ? .clear : Palette.line))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("RPE \(value) z 10")
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }

            Field(title: "Skóra", value: nil) {
                ChipFlow {
                    ForEach(SkinState.allCases, id: \.self) { state in
                        FilterChip(isOn: skin == state) {
                            skin = skin == state ? nil : state
                        } content: {
                            Text(state.polishName)
                        }
                    }
                }
            }

            Field(title: "Coś boli?", value: nil) {
                ChipFlow {
                    ForEach(BodyArea.allCases, id: \.self) { area in
                        let isOn = pain.contains(area)
                        FilterChip(isOn: isOn, action: {
                            if isOn { pain.remove(area) } else { pain.insert(area) }
                        }, tint: Palette.coral) {
                            Text(area.polishName)
                        }
                    }
                }
            }

            if hasChanges {
                Button("Zapisz samopoczucie") { save() }
                    .buttonStyle(.pillSecondary)
                    .transition(.opacity)
            } else if log.wellbeing != nil {
                Label("Zapisane", systemImage: "checkmark")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.snappy, value: hasChanges)
        .sensoryFeedback(.selection, trigger: energy)
        .sensoryFeedback(.selection, trigger: rpe)
    }

    private func syncFromLog() {
        guard log.wellbeing != savedSnapshot else { return }
        savedSnapshot = log.wellbeing
        energy = log.wellbeing?.energy
        rpe = log.wellbeing?.rpe
        skin = log.wellbeing?.skin
        pain = Set(log.wellbeing?.painAreas ?? [])
    }

    /// The form differs from what is saved (or queued).
    private var hasChanges: Bool {
        let saved = log.wellbeing
        return energy != saved?.energy || rpe != saved?.rpe || skin != saved?.skin
            || pain != Set(saved?.painAreas ?? [])
    }

    /// Queued in the outbox: saved locally at once, sent when online.
    private func save() {
        log.saveWellbeing(energy: energy, rpe: rpe, skin: skin, painAreas: pain)
    }
}

/// A labelled row of the wellbeing card.
private struct Field<Content: View>: View {
    let title: String
    let value: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                if let value {
                    Text(value)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                }
            }
            content
        }
    }
}

/// Chips that wrap onto the next line when they run out of room.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
