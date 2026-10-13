import BoulderKit
import SwiftUI

/// A sector photo with a colored pin for every active problem.
struct SectorPhotoView: View {
    let photo: SectorPhoto
    let problems: [ActiveProblem]
    let highlighted: Set<UUID>
    let topped: Set<UUID>
    var gradeLabels: [UUID: String] = [:]
    /// Small photos keep the pins plain; VoiceOver still reads the grade.
    var showsGradeLabels = true
    var sectorName: String?

    var body: some View {
        CachedPhotoView(photo: photo)
        .aspectRatio(photo.aspectRatio, contentMode: .fit)
        .overlay {
            GeometryReader { proxy in
                ForEach(problems) { problem in
                    ProblemPin(
                        color: problem.holdColor,
                        label: showsGradeLabels ? gradeLabels[problem.gradeId] : nil,
                        isHighlighted: highlighted.contains(problem.id),
                        isTopped: topped.contains(problem.id),
                        gradeName: gradeLabels[problem.gradeId],
                        sectorName: sectorName
                    )
                    .position(x: problem.pinX * proxy.size.width, y: problem.pinY * proxy.size.height)
                    // Filtered-out pins are only dimmed on screen; VoiceOver skips them.
                    .accessibilityHidden(!highlighted.contains(problem.id))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ProblemPin: View {
    let color: HoldColor
    /// Grade label shown inside the pin.
    var label: String?
    var isHighlighted = true
    var isTopped = false
    /// Result logged in the session being summarized.
    var sessionResult: AscentResult?
    /// For VoiceOver: the grade when it is not drawn in the pin, and the sector.
    var gradeName: String?
    var sectorName: String?
    /// On the session screen the pin's value is the day's result, "brak" included.
    var isSessionPin = false

    private var ink: Color { color == .white || color == .yellow ? .black : .white }

    var body: some View {
        Circle()
            .fill(color.swatch)
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(isTopped ? Palette.sky : .white, lineWidth: isTopped ? 3 : 2))
            .overlay {
                if let label {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(ink)
                } else if isTopped {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(ink)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Done is never told by the blue ring alone: a tick when the grade fills the pin.
                if isTopped && label != nil && sessionResult == nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 13, height: 13)
                        .background(Palette.sky, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 1))
                        .offset(x: 4, y: 4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let sessionResult {
                    Pictogram(kind: sessionResult.pictogram, size: 18)
                        .background(Palette.paper, in: Circle())
                        .offset(x: 8, y: -8)
                }
            }
            .shadow(radius: 2)
            .opacity(isHighlighted || sessionResult != nil ? 1 : 0.25)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(grade: gradeName ?? label, color: color, sector: sectorName))
            .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if let sessionResult { return sessionResult.polishName.lowercased() }
        if isSessionPin { return "brak" }
        return isTopped ? "zrobiony" : ""
    }
}
