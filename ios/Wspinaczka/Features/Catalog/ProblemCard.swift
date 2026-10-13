import BoulderKit
import SwiftUI

/// The problem picked on a sector photo: grade and color, what its route
/// shows, and whether it changed lately.
struct ProblemCard: View {
    let problem: ActiveProblem
    let grade: String?
    let route: [RouteHold]
    let freshness: Freshness?
    /// Regraded or rerouted after I topped it.
    let changedAfterMyTop: Bool
    let isStaff: Bool
    let onEditRoute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProblemPin(color: problem.holdColor, label: grade, isFresh: freshness != nil)
                    .scaleEffect(1.3)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.display(.headline))
                        .foregroundStyle(Palette.ink)
                    Text(routeSummary)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
            if let freshnessText {
                Label(freshnessText, systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.mustardText)
            }
            if changedAfterMyTop {
                Label("Zmieniony po Twoim przejściu", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            if isStaff {
                Button(route.isEmpty ? "Zaznacz trasę" : "Edytuj trasę", systemImage: "point.topleft.down.to.point.bottomright.curvepath", action: onEditRoute)
                    .buttonStyle(.pillSecondary)
            }
        }
        .paperCard()
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        let color = problem.holdColor.polishName.capitalized
        if let name = problem.name { return "\(name) · \(color) \(grade ?? "")" }
        return "\(color) \(grade ?? "")"
    }

    private var routeSummary: String {
        guard !route.isEmpty else { return "Start przy pinezce. Trasa niezaznaczona." }
        let hands = route.filter { $0.role == .hand }.count
        let hasTop = route.contains { $0.role == .top }
        var parts = ["start"]
        if hands > 0 { parts.append(Self.holds(hands)) }
        if hasTop { parts.append("top") }
        return parts.joined(separator: " · ").capitalizedFirst
    }

    private var freshnessText: String? {
        switch freshness {
        case .new:
            return "Nowy problem"
        case let .changed(kind, at):
            let what = switch kind {
            case .grade: "nowa wycena"
            case .route: "zmieniona trasa"
            case .both: "nowa wycena i trasa"
            }
            return "Zaktualizowany \(at.formatted(.relative(presentation: .named))): \(what)"
        case nil:
            return nil
        }
    }

    /// "1 chwyt", "3 chwyty", "7 chwytów".
    static func holds(_ count: Int) -> String {
        let lastTwo = count % 100, last = count % 10
        if count == 1 { return "1 chwyt" }
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "\(count) chwyty" }
        return "\(count) chwytów"
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
