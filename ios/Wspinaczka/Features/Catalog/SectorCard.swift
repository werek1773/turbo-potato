import BoulderKit
import SwiftUI

/// A sector photo with a colored pin for every active problem.
struct SectorCard: View {
    let sector: Sector
    let photo: SectorPhoto?
    let problems: [ActiveProblem]
    let highlighted: Set<UUID>
    let topped: Set<UUID>
    var gradeLabels: [UUID: String] = [:]
    var upcomingReset: UpcomingReset?
    /// Shown to managers and routesetters.
    var staffActions: SectorStaffActions?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sector.name).font(.title3.bold())
                Spacer()
                Text("\(problems.count) problemów")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let staffActions {
                    Menu {
                        Button(photo == nil ? "Dodaj zdjęcie sektora" : "Przykrętka / nowe zdjęcie",
                               systemImage: "camera", action: staffActions.newPhoto)
                        if photo != nil {
                            Button("Problemy i pinezki", systemImage: "mappin.and.ellipse", action: staffActions.editPins)
                        }
                        Button("Data następnej przykrętki", systemImage: "calendar.badge.clock", action: staffActions.planReset)
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
                SectorPhotoView(photo: photo, problems: problems, highlighted: highlighted, topped: topped,
                                gradeLabels: gradeLabels)
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

struct SectorStaffActions {
    let newPhoto: () -> Void
    let editPins: () -> Void
    let planReset: () -> Void
}
