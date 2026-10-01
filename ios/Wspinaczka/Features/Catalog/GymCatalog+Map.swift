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

    /// Wall color on the map: grey dashed without a photo, orange when a
    /// reset is close, accent otherwise; dimmed when the filter excludes it.
    func mapStyle(for sector: Sector) -> SectorMapStyle {
        guard photo(of: sector) != nil else {
            return SectorMapStyle(color: .gray, dashed: true, isDimmed: !filter.isEmpty)
        }
        let matching = matchingCount(in: sector)
        let soon = upcomingReset(for: sector).map { $0.daysLeft <= 2 } ?? false
        return SectorMapStyle(
            color: soon ? .orange : .accentColor,
            isDimmed: !filter.isEmpty && matching == 0,
            badge: matching > 0 ? "\(matching)" : nil
        )
    }
}
