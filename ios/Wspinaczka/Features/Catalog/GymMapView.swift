import BoulderKit
import SwiftUI

/// How a sector's wall is painted on the map.
struct SectorMapStyle {
    var color: Color
    var dashed = false
    /// A reset is announced within two days: mustard wash under the wall.
    var isResetSoon = false
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

/// The gym drawn like its reset board, without names, in the same ink line
/// as the drawings: mats in light moss, walls drawn in walking order, every
/// problem as a dot of its hold color, and the doors. The ink boils, draws
/// in and filters on the 8 fps clock; selection is smooth.
struct GymMapView: View {
    let plan: FloorPlan
    let sectors: [Sector]
    let style: (Sector) -> SectorMapStyle
    let dots: (Sector) -> [MapDot]
    @Binding var selection: UUID?

    @State private var drawStart = Date()
    @State private var filterChange = Date.distantPast
    @State private var changedDots: Set<UUID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mapped: [(sector: Sector, path: [MapPoint])] {
        sectors.compactMap { sector in sector.mapPath.map { (sector, $0) } }
    }

    var body: some View {
        let allDots = mapped.map { (sector: $0.sector, dots: dots($0.sector)) }
        let matching = Set(allDots.flatMap(\.dots).filter(\.isMatching).map(\.id))
        TimelineView(.animation(minimumInterval: 1 / StopMotion.fps, paused: reduceMotion)) { timeline in
            let frame = reduceMotion ? 1000 : StopMotion.frame(at: timeline.date, since: drawStart)
            let sinceFilter = StopMotion.frame(at: timeline.date, since: filterChange)
            GeometryReader { proxy in
                let size = proxy.size
                let joints = boundaries(in: size)
                ZStack(alignment: .topLeading) {
                    ForEach(plan.mats.indices, id: \.self) { index in
                        PlanShape(points: plan.mats[index], isClosed: true).fill(Palette.mat)
                    }
                    ForEach(plan.outlines.indices, id: \.self) { index in
                        PlanShape(points: plan.outlines[index])
                            .stroke(Palette.line, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }
                    // Climbing wall between sectors (unlabeled on the board): drawn like
                    // the rest of the wall so it never reads as a gap.
                    ForEach(plan.walls.indices, id: \.self) { index in
                        PlanShape(points: plan.walls[index], boilFrame: reduceMotion ? nil : frame, salt: Double(500 + index * 7))
                            .stroke(Palette.ink, style: StrokeStyle(lineWidth: Self.inkWidth, lineCap: .round, lineJoin: .round))
                            .opacity(frame < 2 ? 0 : (selection == nil ? 1 : 0.5))
                    }
                    ForEach(Array(allDots.enumerated()), id: \.element.sector.id) { order, item in
                        if let path = item.sector.mapPath {
                            wall(item.sector, path: path, order: order, frame: frame)
                            holds(item.dots, path: path, order: order, frame: frame, sinceFilter: sinceFilter, size: size)
                        }
                    }
                    // Where one wall ends and the next begins: a short tick
                    // across the line, added once every wall is drawn.
                    let isPlanDrawn = Double(frame) >= Double(max(allDots.count - 1, 0)) * 0.9 + 3
                    ForEach(joints.indices, id: \.self) { index in
                        tick(joints[index], index: index, size: size, frame: frame)
                            .opacity(isPlanDrawn ? (selection == nil ? 0.7 : 0.35) : 0)
                            .animation(.snappy, value: selection)
                    }
                    ForEach(plan.entrances, id: \.self) { door in
                        Pictogram(kind: .door, size: 26)
                            .position(x: door.x * size.width, y: door.y * size.height)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    select(at: location, size: size)
                }
            }
        }
        .aspectRatio(plan.aspect, contentMode: .fit)
        .onAppear { drawStart = .now }
        .onChange(of: matching) { old, new in
            changedDots = old.symmetricDifference(new)
            filterChange = .now
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan ścianki")
    }

    private static let inkWidth: CGFloat = 2.4

    @ViewBuilder
    private func wall(_ sector: Sector, path: [MapPoint], order: Int, frame: Int) -> some View {
        let wallStyle = style(sector)
        let isSelected = selection == sector.id
        let isFaded = selection != nil && !isSelected
        // Three frames per wall, each starting a little after the previous one.
        let drawn = min(1, max(0, (Double(frame) - Double(order) * 0.9) / 3))
        ZStack {
            // A wide wash of color under the ink: moss for the chosen wall,
            // mustard where a reset is coming. Square ends, so the wash stops
            // at the boundary ticks instead of spilling onto the next wall.
            PlanShape(points: path)
                .stroke(isSelected ? Palette.moss : Palette.mustard,
                        style: StrokeStyle(lineWidth: isSelected ? 12 : 7, lineCap: .butt, lineJoin: .round))
                .opacity(drawn < 1 ? 0 : (isSelected ? 1 : (wallStyle.isResetSoon && !isFaded ? 0.55 : 0)))
            PlanShape(points: path, boilFrame: reduceMotion ? nil : frame, salt: Double(order * 11))
                .trim(from: 0, to: drawn)
                .stroke(Palette.ink,
                        style: StrokeStyle(lineWidth: Self.inkWidth, lineCap: .round, lineJoin: .round,
                                           dash: wallStyle.dashed ? [4, 6] : []))
                .opacity(drawn == 0 ? 0 : (wallStyle.isDimmed ? 0.35 : (isFaded ? 0.5 : 1)))
        }
        .animation(.snappy, value: selection)
            .accessibilityElement()
            .accessibilityLabel(sector.name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { selection = sector.id }
    }

    private func holds(_ dots: [MapDot], path: [MapPoint], order: Int, frame: Int, sinceFilter: Int, size: CGSize) -> some View {
        let scaled = path.map { MapPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let offset = 11.0
        return ForEach(dots) { dot in
            if let spot = PlanGeometry.point(along: scaled, at: dot.fraction) {
                // Pop in: nothing, one frame too big, then settled.
                let appear = Double(frame) - (Double(order) * 0.9 + 2 + dot.fraction * 2)
                let scale = appear < 0 ? 0 : (appear < 1 ? 1.5 : 1)
                // Filter: two steps, half-way then the final opacity.
                let target = dot.isMatching ? 1.0 : 0.12
                let opacity = changedDots.contains(dot.id) && sinceFilter < 1 ? 0.55 : target
                Circle()
                    .fill(dot.color.swatch)
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .stroke(dot.isTopped ? Palette.ink : Palette.ink.opacity(dot.color == .white ? 0.3 : 0),
                                    lineWidth: dot.isTopped ? 1.8 : 0.6)
                            .padding(dot.isTopped ? -1.5 : 0)
                    }
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .position(x: spot.point.x + spot.normal.x * offset, y: spot.point.y + spot.normal.y * offset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Joints between stretches of wall (sectors and plain wall), in view points.
    private func boundaries(in size: CGSize) -> [(point: MapPoint, across: MapPoint)] {
        guard size.width > 0, size.height > 0 else { return [] }
        let lines = (mapped.map { $0.path } + plan.walls).map { line in
            line.map { MapPoint(x: $0.x * size.width, y: $0.y * size.height) }
        }
        return PlanGeometry.joints(of: lines, tolerance: 1)
    }

    /// A short ink tick across the wall at a joint, thinner than the wall.
    private func tick(_ joint: (point: MapPoint, across: MapPoint), index: Int, size: CGSize, frame: Int) -> some View {
        let half = 4.5
        let ends = [-half, half].map { offset in
            MapPoint(x: (joint.point.x + joint.across.x * offset) / size.width,
                     y: (joint.point.y + joint.across.y * offset) / size.height)
        }
        return PlanShape(points: ends, boilFrame: reduceMotion ? nil : frame, salt: Double(900 + index * 13))
            .stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func select(at location: CGPoint, size: CGSize) {
        let paths = mapped.map { item in
            (id: item.sector.id, points: item.path.map { MapPoint(x: $0.x * size.width, y: $0.y * size.height) })
        }
        let hit = PlanGeometry.nearest(to: MapPoint(x: location.x, y: location.y), among: paths, maxDistance: 30)
        selection = hit == selection ? nil : hit
    }
}

/// A polyline (or closed polygon) of plan points, scaled to the view. With
/// `boilFrame`, every point moves a hair per frame, like a redrawn ink line.
struct PlanShape: Shape {
    let points: [MapPoint]
    var isClosed = false
    var boilFrame: Int?
    var salt: Double = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            var scaled = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
            if let frame = boilFrame {
                let i = Double(index)
                scaled.x += (Wobble.noise(Double(frame) * 31 + i * 7 + salt) - 0.5) * 2
                scaled.y += (Wobble.noise(Double(frame) * 57 + i * 13 + salt) - 0.5) * 2
            }
            if index == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
        }
        if isClosed { path.closeSubpath() }
        return path
    }
}

/// The plan alone, small and still: used on gym cards.
struct MiniMapView: View {
    let plan: FloorPlan
    let paths: [[MapPoint]]

    var body: some View {
        ZStack {
            ForEach(plan.mats.indices, id: \.self) { index in
                PlanShape(points: plan.mats[index], isClosed: true).fill(Palette.mat)
            }
            ForEach(paths.indices, id: \.self) { index in
                PlanShape(points: paths[index])
                    .stroke(Palette.moss, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(plan.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
