import BoulderKit
import SwiftUI

/// A sector photo with a colored pin for every active problem.
struct SectorPhotoView: View {
    let photo: SectorPhoto
    let problems: [ActiveProblem]
    let highlighted: Set<UUID>
    let topped: Set<UUID>
    var gradeLabels: [UUID: String] = [:]

    var body: some View {
        AsyncImage(url: Backend.shared.photoURL(for: photo)) { phase in
            switch phase {
            case let .success(image):
                image.resizable()
            default:
                Rectangle().fill(.quaternary)
            }
        }
        .aspectRatio(photo.aspectRatio, contentMode: .fit)
        .overlay {
            GeometryReader { proxy in
                ForEach(problems) { problem in
                    ProblemPin(
                        color: problem.holdColor,
                        label: gradeLabels[problem.gradeId],
                        isHighlighted: highlighted.contains(problem.id),
                        isTopped: topped.contains(problem.id)
                    )
                    .position(x: problem.pinX * proxy.size.width, y: problem.pinY * proxy.size.height)
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

    private var ink: Color { color == .white || color == .yellow ? .black : .white }

    var body: some View {
        Circle()
            .fill(color.swatch)
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(isTopped ? Color.green : .white, lineWidth: isTopped ? 3 : 2))
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
            .overlay(alignment: .topTrailing) {
                if let sessionResult {
                    Image(systemName: sessionResult.symbol)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 16, height: 16)
                        .background(sessionResult.tint, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: 7, y: -7)
                }
            }
            .shadow(radius: 2)
            .opacity(isHighlighted || sessionResult != nil ? 1 : 0.25)
            .accessibilityLabel("Problem \(label.map { "\($0), " } ?? "")\(color.polishName)\(isTopped ? ", zrobiony" : "")")
    }
}
