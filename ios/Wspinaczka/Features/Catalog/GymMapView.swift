import BoulderKit
import SwiftUI

/// How a sector's wall is painted on the map.
struct SectorMapStyle {
    var color: Color
    var dashed = false
    var isDimmed = false
}

/// One problem standing at its wall, in the color of its holds.
struct MapDot: Identifiable {
    let id: UUID
    /// Position along the wall, 0 = left edge of the sector photo.
    let fraction: Double
    let color: HoldColor
    let isTopped: Bool
    let isMatching: Bool
}

/// The gym drawn like its reset board, without names: mats, walls in walking
/// order, every problem as a dot of its hold color, and the doors.
struct GymMapView: View {
    let plan: FloorPlan
    let sectors: [Sector]
    let style: (Sector) -> SectorMapStyle
    let dots: (Sector) -> [MapDot]
    @Binding var selection: UUID?

    @State private var isDrawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mapped: [(sector: Sector, path: [MapPoint])] {
        sectors.compactMap { sector in sector.mapPath.map { (sector, $0) } }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                ForEach(plan.mats.indices, id: \.self) { index in
                    PlanShape(points: plan.mats[index], isClosed: true)
                        .fill(Palette.mat)
                        .opacity(isDrawn ? 1 : 0)
                        .animation(.easeOut(duration: 0.5), value: isDrawn)
                }
                ForEach(plan.outlines.indices, id: \.self) { index in
                    PlanShape(points: plan.outlines[index])
                        .stroke(Palette.line, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                ForEach(plan.walls.indices, id: \.self) { index in
                    PlanShape(points: plan.walls[index])
                        .stroke(Palette.line, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(mapped.enumerated()), id: \.element.sector.id) { order, item in
                    wall(item.sector, path: item.path, order: order)
                    holds(item.sector, path: item.path, order: order, size: size)
                }
                ForEach(plan.entrances, id: \.self) { door in
                    Circle()
                        .fill(Palette.door)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Image(systemName: "door.left.hand.open")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .scaleEffect(isDrawn ? 1 : 0.2)
                        .opacity(isDrawn ? 1 : 0)
                        .animation(.spring(duration: 0.5, bounce: 0.5), value: isDrawn)
                        .position(x: door.x * size.width, y: door.y * size.height)
                        .accessibilityLabel("Wejście")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                select(at: location, size: size)
            }
        }
        .aspectRatio(plan.aspect, contentMode: .fit)
        .onAppear { isDrawn = true }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan ścianki")
    }

    @ViewBuilder
    private func wall(_ sector: Sector, path: [MapPoint], order: Int) -> some View {
        let wallStyle = style(sector)
        let isSelected = selection == sector.id
        let isFaded = selection != nil && !isSelected
        PlanShape(points: path)
            .trim(from: 0, to: isDrawn ? 1 : 0)
            .stroke(isSelected ? Palette.olive : wallStyle.color,
                    style: StrokeStyle(lineWidth: isSelected ? 10 : 6, lineCap: .round, lineJoin: .round,
                                       dash: wallStyle.dashed && !isSelected ? [5, 7] : []))
            .opacity(wallStyle.isDimmed || isFaded ? 0.35 : 1)
            .animation(.easeOut(duration: 0.4).delay(reduceMotion ? 0 : 0.15 + Double(order) * 0.08), value: isDrawn)
            .animation(.snappy, value: selection)
            .accessibilityElement()
            .accessibilityLabel(sector.name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { selection = sector.id }
    }

    private func holds(_ sector: Sector, path: [MapPoint], order: Int, size: CGSize) -> some View {
        let scaled = path.map { MapPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let offset = 11.0
        return ForEach(dots(sector)) { dot in
            if let spot = PlanGeometry.point(along: scaled, at: dot.fraction) {
                Circle()
                    .fill(dot.color.swatch)
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle().stroke(dot.isTopped ? Palette.ink : Palette.ink.opacity(dot.color == .white ? 0.3 : 0),
                                        lineWidth: dot.isTopped ? 1.8 : 0.6)
                            .padding(dot.isTopped ? -1.5 : 0)
                    }
                    .scaleEffect(isDrawn ? (dot.isMatching ? 1 : 0.5) : 0)
                    .opacity(dot.isMatching ? 1 : 0.12)
                    .animation(.spring(duration: 0.45, bounce: 0.55)
                        .delay(reduceMotion ? 0 : 0.35 + Double(order) * 0.08 + dot.fraction * 0.2), value: isDrawn)
                    .animation(.smooth, value: dot.isMatching)
                    .position(x: spot.point.x + spot.normal.x * offset, y: spot.point.y + spot.normal.y * offset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func select(at location: CGPoint, size: CGSize) {
        let paths = mapped.map { item in
            (id: item.sector.id, points: item.path.map { MapPoint(x: $0.x * size.width, y: $0.y * size.height) })
        }
        let hit = PlanGeometry.nearest(to: MapPoint(x: location.x, y: location.y), among: paths, maxDistance: 30)
        selection = hit == selection ? nil : hit
    }
}

/// A polyline (or closed polygon) of plan points, scaled to the view.
struct PlanShape: Shape {
    let points: [MapPoint]
    var isClosed = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        if isClosed { path.closeSubpath() }
        return path
    }
}

/// The plan alone, drawing itself in: used on gym cards.
struct MiniMapView: View {
    let plan: FloorPlan
    let paths: [[MapPoint]]

    @State private var isDrawn = false

    var body: some View {
        ZStack {
            ForEach(plan.mats.indices, id: \.self) { index in
                PlanShape(points: plan.mats[index], isClosed: true).fill(Palette.mat)
            }
            ForEach(paths.indices, id: \.self) { index in
                PlanShape(points: paths[index])
                    .trim(from: 0, to: isDrawn ? 1 : 0)
                    .stroke(Palette.chartreuse, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .animation(.easeOut(duration: 0.35).delay(0.2 + Double(index) * 0.06), value: isDrawn)
            }
        }
        .aspectRatio(plan.aspect, contentMode: .fit)
        .onAppear { isDrawn = true }
        .accessibilityHidden(true)
    }
}
