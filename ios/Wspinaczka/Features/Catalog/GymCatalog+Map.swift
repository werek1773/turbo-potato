import BoulderKit
import SwiftUI

extension GymCatalog {
    /// Problems in the sector that match the current filter.
    func matchingCount(in sector: Sector) -> Int {
        let visible = visibleProblemIds
        return problems(in: sector).filter { visible.contains($0.id) }.count
    }

    func toppedCount(in sector: Sector) -> Int {
        let topped = toppedProblemIds
        return problems(in: sector).filter { topped.contains($0.id) }.count
    }

    /// Wall color on the map: mustard when a reset is close, moss otherwise;
    /// dashed without a photo; dimmed when the filter excludes it. An
    /// announced reset shows whether or not the wall has a photo yet.
    func mapStyle(for sector: Sector) -> SectorMapStyle {
        let isResetSoon = upcomingReset(for: sector).map { $0.daysLeft <= 2 } ?? false
        guard photo(of: sector) != nil else {
            return SectorMapStyle(color: isResetSoon ? Palette.mustard : Palette.line, dashed: true,
                                  isResetSoon: isResetSoon, isDimmed: !filter.isEmpty)
        }
        return SectorMapStyle(
            color: isResetSoon ? Palette.mustard : Palette.moss,
            isResetSoon: isResetSoon,
            isDimmed: !filter.isEmpty && matchingCount(in: sector) == 0
        )
    }

    /// Every active problem of the sector as a dot along its wall.
    func mapDots(for sector: Sector) -> [MapDot] {
        let visible = visibleProblemIds
        let topped = toppedProblemIds
        return problems(in: sector).map { problem in
            MapDot(id: problem.id, fraction: problem.pinX, color: problem.holdColor,
                   isTopped: topped.contains(problem.id), isMatching: visible.contains(problem.id))
        }
    }
}
