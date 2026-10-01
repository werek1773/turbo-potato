import BoulderKit
import SwiftUI

/// "4 · 7/12" chips: tap a grade to show only its problems.
struct GradeFilterBar: View {
    @Bindable var catalog: GymCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(catalog.coverage) { level in
                        let selected = catalog.filter.gradeOrders == level.grade.sortOrder...level.grade.sortOrder
                        Button {
                            catalog.filter.gradeOrders = selected
                                ? nil
                                : level.grade.sortOrder...level.grade.sortOrder
                        } label: {
                            VStack(spacing: 2) {
                                Text(level.grade.label).font(.headline)
                                Text("\(level.topped)/\(level.active)").font(.caption2.monospacedDigit())
                            }
                            .frame(minWidth: 44)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(.accentColor) : .regular, in: .capsule)
                    }
                }
            }
            Toggle("Tylko niezrobione", isOn: $catalog.filter.onlyNotTopped)
            if let lastVisit = catalog.lastVisit {
                Toggle("Nowe od ostatniej wizyty", isOn: Binding(
                    get: { catalog.filter.setAfter != nil },
                    set: { catalog.filter.setAfter = $0 ? lastVisit : nil }
                ))
            }
        }
    }
}
