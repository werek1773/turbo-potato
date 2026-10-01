import BoulderKit
import SwiftUI

/// A sector photo with a colored pin for every active problem.
struct SectorCard: View {
    let sector: Sector
    let photo: SectorPhoto?
    let problems: [ActiveProblem]
    let highlighted: Set<UUID>
    let topped: Set<UUID>
    var upcomingReset: UpcomingReset?
    /// Shown to staff: announce or change the next reset date.
    var onPlanReset: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sector.name).font(.title3.bold())
                Spacer()
                Text("\(problems.count) problemów")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let onPlanReset {
                    Menu {
                        Button("Data następnej przykrętki", systemImage: "calendar.badge.clock", action: onPlanReset)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("Opcje sektora")
                }
            }
            if let upcomingReset {
                ResetBadge(reset: upcomingReset)
            } else if let next = sector.nextResetOn {
                Label("Przykrętka \(ResetBadge.dayText(next))", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let photo {
                SectorPhotoView(photo: photo, problems: problems, highlighted: highlighted, topped: topped)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        Label("Brak zdjęcia sektora", systemImage: "camera")
                            .foregroundStyle(.secondary)
                    }
            }
            if let lastReset = sector.lastResetAt {
                Text("Przykrętka: \(lastReset.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SectorPhotoView: View {
    let photo: SectorPhoto
    let problems: [ActiveProblem]
    let highlighted: Set<UUID>
    let topped: Set<UUID>

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
    var isHighlighted = true
    var isTopped = false

    var body: some View {
        Circle()
            .fill(color.swatch)
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .overlay {
                if isTopped {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(color == .white || color == .yellow ? .black : .white)
                }
            }
            .shadow(radius: 2)
            .opacity(isHighlighted ? 1 : 0.25)
            .accessibilityLabel("Problem \(color.polishName)\(isTopped ? ", zrobiony" : "")")
    }
}
