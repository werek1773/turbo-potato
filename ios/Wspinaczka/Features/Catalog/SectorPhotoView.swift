import BoulderKit
import SwiftUI

/// A sector photo with every active problem on it. A problem with a route
/// has its start hold ringed and its grade beside it; one without shows its
/// pin. With `selected`, the wall dims around that problem's route.
struct SectorPhotoView: View {
    let photo: SectorPhoto
    let problems: [ActiveProblem]
    let highlighted: Set<UUID>
    let topped: Set<UUID>
    var gradeLabels: [UUID: String] = [:]
    var routes: [UUID: [RouteHold]] = [:]
    /// New or changed since my last visit.
    var fresh: Set<UUID> = []
    var selected: UUID?
    var onSelect: ((ActiveProblem) -> Void)?

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
                if let selectedProblem, !(routes[selectedProblem.id] ?? []).isEmpty {
                    RouteOverlay(route: routes[selectedProblem.id] ?? [], color: selectedProblem.holdColor)
                        .transition(.opacity)
                } else {
                    StartRings(items: startRings)
                }
                ForEach(problems) { problem in
                    pin(for: problem)
                        .position(TagPlacement.point(for: problem, route: routes[problem.id] ?? [], in: proxy.size))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    private var selectedProblem: ActiveProblem? {
        selected.flatMap { id in problems.first { $0.id == id } }
    }

    private var startRings: [StartRings.Item] {
        problems.flatMap { problem in
            (routes[problem.id] ?? [])
                .filter { $0.role == .start }
                .map { StartRings.Item(hold: $0, color: problem.holdColor, isHighlighted: highlighted.contains(problem.id)) }
        }
    }

    @ViewBuilder
    private func pin(for problem: ActiveProblem) -> some View {
        let isLit = selected == nil ? highlighted.contains(problem.id) : selected == problem.id
        let marker = ProblemPin(
            color: problem.holdColor,
            label: gradeLabels[problem.gradeId],
            isHighlighted: isLit,
            isTopped: topped.contains(problem.id),
            isFresh: fresh.contains(problem.id)
        )
        if let onSelect {
            Button { onSelect(problem) } label: {
                marker
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            marker
        }
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
    /// New or changed since my last visit: a mustard mark, the color of
    /// announced resets.
    var isFresh = false

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
            .overlay(alignment: .topLeading) {
                if isFresh {
                    Circle()
                        .fill(Palette.mustard)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Palette.paper, lineWidth: 2))
                        .offset(x: -3, y: -3)
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
            .accessibilityLabel("Problem \(label.map { "\($0), " } ?? "")\(color.polishName)\(isTopped ? ", zrobiony" : "")\(isFresh ? ", nowość" : "")")
    }
}
