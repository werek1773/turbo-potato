import BoulderKit
import SwiftUI

/// Grade, hold color, style and name of a problem: optimized for setting a
/// whole sector quickly (big tap targets, last values remembered).
struct ProblemForm: View {
    @Binding var draft: ProblemDraft
    let grades: [Grade]

    var body: some View {
        Section("Wycena") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(grades) { grade in
                    let selected = draft.gradeId == grade.id
                    Button {
                        draft.gradeId = grade.id
                    } label: {
                        Text(grade.label)
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selected ? Color.accentColor : Color.secondary.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }

        Section("Kolor chwytów") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(HoldColor.allCases, id: \.self) { color in
                    let selected = draft.color == color
                    Button {
                        draft.color = color
                    } label: {
                        Circle()
                            .fill(color.swatch)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: selected ? 4 : 0).padding(-4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.polishName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }

        Section("Styl (opcjonalnie)") {
            FlowTags(selection: $draft.styleTags)
            TextField("Nazwa (opcjonalnie)", text: $draft.name)
        }
    }
}

/// Toggle chips for style tags.
struct FlowTags: View {
    @Binding var selection: Set<StyleTag>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            ForEach(StyleTag.allCases, id: \.self) { tag in
                let selected = selection.contains(tag)
                Button {
                    if selected { selection.remove(tag) } else { selection.insert(tag) }
                } label: {
                    Text(tag.polishName)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                                    in: Capsule())
                        .overlay(Capsule().stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
