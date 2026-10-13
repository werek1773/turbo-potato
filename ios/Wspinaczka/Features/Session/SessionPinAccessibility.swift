import BoulderKit
import SwiftUI

extension View {
    /// VoiceOver on a pin of "Podsumuj sesję": double tap cycles the result
    /// like a tap (brak → top → flash → projekt), swiping up or down steps
    /// through it either way, and "Szczegóły" stands in for the long press.
    func sessionPinAccessibility(
        log: SessionLog,
        problem: ActiveProblem,
        onDetails: @escaping (ActiveProblem) -> Void
    ) -> some View {
        accessibilityAddTraits(.isButton)
            .accessibilityHint("Stuknij dwukrotnie, aby zmienić wynik. Przesuń w górę lub w dół, aby go wybrać.")
            .accessibilityAction { log.cycle(problem) }
            .accessibilityAdjustableAction { direction in
                let current = log.results[problem.id]
                let canFlash = log.flashable.contains(problem.id)
                let result: AscentResult? = switch direction {
                case .increment: AscentResult.next(after: current?.result, canFlash: canFlash)
                case .decrement: AscentResult.previous(before: current?.result, canFlash: canFlash)
                @unknown default: current?.result
                }
                guard result != current?.result else { return }
                log.set(problem, result: result, keepingDetailsOf: current)
            }
            .accessibilityAction(named: "Szczegóły") { onDetails(problem) }
    }
}
