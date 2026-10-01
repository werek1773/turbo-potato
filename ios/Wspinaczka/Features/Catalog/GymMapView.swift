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
/// order, every problem as a dot of its hold color, and the doors. Drawing in
/// and filtering run on the 8 fps clock; selection is smooth.
struct GymMapView: View {
    let plan: FloorPlan
    let sectors: [Sector]
    let style: (Sector) -> SectorMapStyle
    let dots: (Sector) -> [MapDot]
    @Binding var selection: UUID?

    @State private var drawStart = Date()
    @State private var filterChange = Date.distantPast
    @State private var changedDots: Set<UUID> = []
    @State private var isTicking = true
    @State private var tickGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mapped: [(sector: Sector, path: [MapPoint])] {
        sectors.compactMap { sector in sector.mapPath.map { (sector, $0) } }
    }

    /// Frames until the last wall is drawn and its dots have settled.
    private var drawFrames: Int { Int(Double(max(mapped.count - 1, 0)) * 0.9) + 6 }

    var body: some View {
        let allDots = mapped.map { (sector: $0.sector, dots: dots($0.sector)) }
        let matching = Set(allDots.flatMap(\.dots).filter(\.isMatching).map(\.id))
        TimelineView(.animation(minimumInterval: 1 / StopMotion.fps, paused: !isTicking || reduceMotion)) { timeline in
            let frame = reduceMotion ? 1000 : StopMotion.frame(at: timeline.date, since: drawStart)
            let sinceFilter = StopMotion.frame(at: timeline.date, since: filterChange)
            GeometryReader { proxy in
                let size = proxy.size
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
                        PlanShape(points: plan.walls[index])
                            .trim(from: 0, to: frame >= 2 ? 1 : 0)
                            .stroke(Palette.moss, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                            .opacity(selection == nil ? 1 : 0.35)
                    }
                    ForEach(Array(allDots.enumerated()), id: \.element.sector.id) { order, item in
                        if let path = item.sector.mapPath {
                            wall(item.sector, path: path, order: order, frame: frame)
                            holds(item.dots, path: path, order: order, frame: frame, sinceFilter: sinceFilter, size: size)
                        }
                    }
                    ForEach(plan.entrances, id: \.self) { door in
                        DoorMarker()
                            .frame(width: 24, height: 24)
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
        .onAppear {
            drawStart = .now
            tick(for: drawFrames)
        }
        .onChange(of: matching) { old, new in
            changedDots = old.symmetricDifference(new)
            filterChange = .now
            tick(for: 3)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan ścianki")
    }

    /// Runs the clock for a few frames, then lets it rest.
    private func tick(for frames: Int) {
        tickGeneration += 1
        let generation = tickGeneration
        isTicking = true
        Task {
            try? await Task.sleep(for: .seconds(Double(frames + 1) / StopMotion.fps))
            if generation == tickGeneration { isTicking = false }
        }
    }

    @ViewBuilder
    private func wall(_ sector: Sector, path: [MapPoint], order: Int, frame: Int) -> some View {
        let wallStyle = style(sector)
        let isSelected = selection == sector.id
        let isFaded = selection != nil && !isSelected
        // Three frames per wall, each starting a little after the previous one.
        let drawn = min(1, max(0, (Double(frame) - Double(order) * 0.9) / 3))
        PlanShape(points: path)
            .trim(from: 0, to: drawn)
            .stroke(isSelected ? Palette.mossDark : wallStyle.color,
                    style: StrokeStyle(lineWidth: isSelected ? 10 : 6, lineCap: .round, lineJoin: .round,
                                       dash: wallStyle.dashed && !isSelected ? [5, 7] : []))
            .opacity(drawn == 0 ? 0 : (wallStyle.isDimmed || isFaded ? 0.35 : 1))
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
