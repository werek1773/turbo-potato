import BoulderKit
import SwiftUI

extension GymCatalog {
    /// Grades that have problems on the wall, easiest first.
    var gradesInUse: [Grade] { coverage.map(\.grade) }

    /// Hold colors on the wall, plus any still chosen in the filter.
    var colorsInUse: [HoldColor] {
        let used = Set(problems.map(\.holdColor)).union(filter.colors)
        return HoldColor.allCases.filter(used.contains)
    }

    /// The coverage counter, within one sector when given.
    func coverageCount(in sector: Sector? = nil) -> CoverageCount {
        var scope = filter
        if let sector { scope.sectorIds = [sector.id] }
        return Coverage.count(problems: problems, grades: gradesById, toppedProblemIds: toppedProblemIds,
                              filter: scope, timeZone: gym.timeZone)
    }

    /// "4" or "4–6" for the chosen grades.
    var gradeRangeText: String? {
        guard let range = filter.gradeOrders else { return nil }
        let labels = grades.filter { range.contains($0.sortOrder) }.sorted { $0.sortOrder < $1.sortOrder }
        guard let first = labels.first, let last = labels.last else { return nil }
        return first.id == last.id ? first.label : "\(first.label)–\(last.label)"
    }

    /// "4: 7 z 12 aktywnych", or "Zrobione: 7 z 12 aktywnych" without a grade.
    func coverageText(in sector: Sector? = nil) -> String {
        let count = coverageCount(in: sector)
        return "\(gradeRangeText ?? "Zrobione"): \(count.topped) z \(count.active) aktywnych"
    }
}

/// Under the grades: quick filter chips, the coverage counter and one-tap reset.
/// In a sector (`sector` set) there is no sector filter and the counter
/// counts that sector only.
struct CatalogFilterBar: View {
    @Bindable var catalog: GymCatalog
    var sector: Sector?

    @State private var isShowingSheet = false

    private var filter: ProblemFilter { catalog.filter }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(isOn: filter.activeCount > 0, action: { isShowingSheet = true }) {
                        Pictogram(kind: .filter, size: 18)
                        Text("Filtry")
                        if filter.activeCount > 0 {
                            Text("\(filter.activeCount)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 6)
                                .background(Palette.paper.opacity(0.9), in: Capsule())
                                .foregroundStyle(Palette.mossDark)
                        }
                    }
                    .accessibilityLabel("Filtry")
                    .accessibilityValue(filter.activeCount > 0 ? "aktywne: \(filter.activeCount)" : "brak")
                    .accessibilityHint("Otwiera wszystkie filtry.")

                    FilterChip(isOn: filter.onlyNotTopped, action: { catalog.filter.onlyNotTopped.toggle() }) {
                        Text("Niezrobione")
                        if filter.onlyNotTopped { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                    }
                    .accessibilityLabel("Niezrobione przeze mnie")

                    if let lastVisit = catalog.lastVisit {
                        FilterChip(isOn: filter.setAfter != nil, action: {
                            catalog.filter.setAfter = filter.setAfter == nil ? lastVisit : nil
                        }) {
                            Text("Nowe od ostatniej wizyty")
                            if filter.setAfter != nil { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                        }
                        .accessibilityLabel("Nowe od mojej ostatniej wizyty")
                    }

                    ForEach(catalog.colorsInUse.filter(filter.colors.contains), id: \.self) { color in
                        FilterChip(isOn: true, action: { catalog.filter.toggle(color) }) {
                            Circle().fill(color.swatch).frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Palette.paper, lineWidth: 1))
                            Text(color.polishName)
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .accessibilityLabel("Kolor \(color.polishName)")
                        .accessibilityHint("Stuknij dwukrotnie, aby usunąć ten filtr.")
                    }

                    if sector == nil {
                        ForEach(catalog.sectors.filter { filter.sectorIds.contains($0.id) }) { sector in
                            FilterChip(isOn: true, action: { catalog.filter.toggleSector(sector.id) }) {
                                Text(sector.name)
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                            }
                            .accessibilityLabel("Sektor \(sector.name)")
                            .accessibilityHint("Stuknij dwukrotnie, aby usunąć ten filtr.")
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    counter
                    Spacer(minLength: 8)
                    resetButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    counter
                    resetButton
                }
            }
        }
        .sensoryFeedback(.selection, trigger: filter)
        .sheet(isPresented: $isShowingSheet) {
            CatalogFilterSheet(catalog: catalog, showsSectors: sector == nil)
        }
    }

    private var counter: some View {
        Text(catalog.coverageText(in: sector))
            .font(.footnote.monospacedDigit())
            .foregroundStyle(Palette.muted)
            .contentTransition(.numericText())
            .animation(.snappy, value: catalog.coverageCount(in: sector))
    }

    @ViewBuilder
    private var resetButton: some View {
        if !filter.isEmpty {
            Button {
                withAnimation(.snappy) { catalog.filter.reset() }
            } label: {
                Label("Wyczyść filtry", systemImage: "xmark.circle")
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.mossDark)
        }
    }
}

/// A capsule like the intro's grade chips: paper when off, moss when on.
/// Chips that toggle add a tick (or a cross) so color is not the only sign.
struct FilterChip<Content: View>: View {
    let isOn: Bool
    let action: () -> Void
    /// Fill of the chip when on (moss; coral for pain).
    var tint: Color = Palette.moss
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                content
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .foregroundStyle(isOn ? Palette.paper : Palette.ink)
            .background(isOn ? tint : Palette.paper, in: Capsule())
            .overlay(Capsule().stroke(isOn ? .clear : Palette.line))
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Every filter at once: grades from–to, hold colors, sectors, not done, new.
struct CatalogFilterSheet: View {
    @Bindable var catalog: GymCatalog
    var showsSectors = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            Form {
                gradeSection
                colorSection
                if showsSectors {
                    sectorSections
                }
                Section {
                    Toggle("Niezrobione przeze mnie", isOn: $catalog.filter.onlyNotTopped)
                    if let lastVisit = catalog.lastVisit {
                        Toggle(isOn: Binding(
                            get: { catalog.filter.setAfter != nil },
                            set: { catalog.filter.setAfter = $0 ? lastVisit : nil }
                        )) {
                            Text("Nowe od mojej ostatniej wizyty")
                            Text("Ostatnio: \(ResetBadge.dayText(lastVisit))")
                        }
                    }
                } footer: {
                    Text(catalog.coverageText())
                        .monospacedDigit()
                }
            }
            .canvasBackground()
            .tint(Palette.moss)
            .navigationTitle("Filtry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Wyczyść") { catalog.filter.reset() }
                        .disabled(catalog.filter.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Grades

    private var gradeSection: some View {
        Section("Wycena") {
            Picker("Od", selection: Binding(
                get: { catalog.filter.gradeOrders?.lowerBound },
                set: { setGrades(lower: $0, upper: catalog.filter.gradeOrders?.upperBound) }
            )) {
                Text("Dowolna").tag(Int?.none)
                ForEach(catalog.gradesInUse) { grade in
                    Text(grade.label).tag(Optional(grade.sortOrder))
                }
            }
            Picker("Do", selection: Binding(
                get: { catalog.filter.gradeOrders?.upperBound },
                set: { setGrades(lower: catalog.filter.gradeOrders?.lowerBound, upper: $0) }
            )) {
                Text("Dowolna").tag(Int?.none)
                ForEach(catalog.gradesInUse) { grade in
                    Text(grade.label).tag(Optional(grade.sortOrder))
                }
            }
        }
    }

    /// One end left open means "from the easiest" or "up to the hardest".
    private func setGrades(lower: Int?, upper: Int?) {
        let orders = catalog.gradesInUse.map(\.sortOrder)
        guard lower != nil || upper != nil, let easiest = orders.min(), let hardest = orders.max() else {
            catalog.filter.gradeOrders = nil
            return
        }
        let from = lower ?? easiest, to = upper ?? hardest
        catalog.filter.gradeOrders = min(from, to)...max(from, to)
    }

    // MARK: Colors

    private var colorSection: some View {
        Section("Kolor chwytów") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 84), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(catalog.colorsInUse, id: \.self) { color in
                    let isOn = catalog.filter.colors.contains(color)
                    Button {
                        catalog.filter.toggle(color)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color.swatch)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Palette.line))
                                .overlay {
                                    if isOn {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.heavy))
                                            .foregroundStyle(color == .white || color == .yellow ? .black : .white)
                                    }
                                }
                            Text(color.polishName)
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .background(isOn ? Palette.mat : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Kolor \(color.polishName)")
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Sectors

    @ViewBuilder
    private var sectorSections: some View {
        ForEach(catalog.areas) { area in
            Section(area.name.map { "Sektory · \($0)" } ?? "Sektory") {
                ForEach(area.sectors) { sector in
                    let isOn = catalog.filter.sectorIds.contains(sector.id)
                    Button {
                        catalog.filter.toggleSector(sector.id)
                    } label: {
                        HStack {
                            Text(sector.name)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if isOn {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Palette.mossDark)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }
}
