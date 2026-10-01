import BoulderKit
import SwiftUI

/// How a sector's wall is painted on the map.
struct SectorMapStyle {
    var color: Color
    var dashed = false
    var isDimmed = false
    var badge: String?
}

/// The gym drawn like its reset board. Tap a wall to open its sector.
struct GymMapView: View {
    let plan: FloorPlan
    let sectors: [Sector]
    let style: (Sector) -> SectorMapStyle
    let onSelect: (Sector) -> Void

    private let wallWidth: CGFloat = 7

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Canvas { context, size in
                    draw(into: &context, size: size)
                }
                // Sector names, placed at the middle of each wall.
                ForEach(sectors.filter { $0.mapPath != nil }) { sector in
                    if let path = sector.mapPath, let mid = PlanGeometry.midpoint(of: path) {
                        let sectorStyle = style(sector)
                        Text(sectorStyle.badge.map { "\(sector.name) · \($0)" } ?? sector.name)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.background.opacity(0.85), in: Capsule())
                            .opacity(sectorStyle.isDimmed ? 0.45 : 1)
                            .position(labelPosition(for: mid, in: size))
                            .allowsHitTesting(false)
                    }
                }
                ForEach(plan.labels, id: \.self) { label in
                    Text(label.text)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .position(x: label.x * size.width, y: label.y * size.height)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                select(at: location, size: size)
            }
        }
        .aspectRatio(plan.aspect, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mapa ścianki")
    }

    private func scaled(_ points: [MapPoint], _ size: CGSize) -> [CGPoint] {
        points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }

    private func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }

    private func draw(into context: inout GraphicsContext, size: CGSize) {
        for outline in plan.outlines {
            context.stroke(polyline(scaled(outline, size)), with: .color(.secondary.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        for wall in plan.walls {
            context.stroke(polyline(scaled(wall, size)), with: .color(.secondary.opacity(0.5)),
                           style: StrokeStyle(lineWidth: wallWidth, lineCap: .round, lineJoin: .round))
        }
        for sector in sectors {
            guard let points = sector.mapPath else { continue }
            let sectorStyle = style(sector)
            let path = polyline(scaled(points, size))
            context.stroke(path, with: .color(sectorStyle.color.opacity(sectorStyle.isDimmed ? 0.3 : 1)),
                           style: StrokeStyle(lineWidth: wallWidth, lineCap: .round, lineJoin: .round,
                                              dash: sectorStyle.dashed ? [8, 6] : []))
            // Dots at sector boundaries, like on the board.
            for point in [scaled(points, size).first, scaled(points, size).last].compactMap({ $0 }) {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                             with: .color(.primary.opacity(0.7)))
            }
        }
    }

    /// Labels sit slightly towards the center of the plan so they do not hide the wall.
    private func labelPosition(for mid: MapPoint, in size: CGSize) -> CGPoint {
        let point = CGPoint(x: mid.x * size.width, y: mid.y * size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = center.x - point.x, dy = center.y - point.y
        let length = max(hypot(dx, dy), 1)
        return CGPoint(x: point.x + dx / length * 22, y: point.y + dy / length * 22)
    }

    private func select(at location: CGPoint, size: CGSize) {
        let paths = sectors.compactMap { sector -> (id: UUID, points: [MapPoint])? in
            guard let points = sector.mapPath else { return nil }
            return (sector.id, points.map { MapPoint(x: $0.x * size.width, y: $0.y * size.height) })
        }
        if let id = PlanGeometry.nearest(to: MapPoint(x: location.x, y: location.y), among: paths, maxDistance: 28),
           let sector = sectors.first(where: { $0.id == id }) {
            onSelect(sector)
        }
    }
}
