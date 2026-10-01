import SwiftUI

/// The app's drawn icons: one hand, a rounded ink line and flat fills from
/// the palette, on a 24×24 grid. Color only where it means what the palette
/// says (moss top, coral flash, plum project, mustard reset); the door, lock
/// and bucket stay neutral. The three results are discs of one size.
struct Pictogram: View {
    enum Kind {
        case door, flash, top, project, chalkBag, lock, reset, map, filter
    }

    let kind: Kind
    var size: CGFloat = 24

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            context.scaleBy(x: scale, y: scale)
            Self.draw(kind, in: &context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let ink = Palette.ink
    private static let line = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)

    private static func outline(_ path: Path, fill: Color?, in context: inout GraphicsContext) {
        if let fill { context.fill(path, with: .color(fill)) }
        context.stroke(path, with: .color(ink), style: line)
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    /// A full circle as two half circles, so halves can be filled separately.
    private static func rightHalf(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        let k = r * 0.5523
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - r))
        path.addCurve(to: CGPoint(x: cx + r, y: cy), control1: CGPoint(x: cx + k, y: cy - r), control2: CGPoint(x: cx + r, y: cy - k))
        path.addCurve(to: CGPoint(x: cx, y: cy + r), control1: CGPoint(x: cx + r, y: cy + k), control2: CGPoint(x: cx + k, y: cy + r))
        path.closeSubpath()
        return path
    }

    static func draw(_ kind: Kind, in context: inout GraphicsContext) {
        switch kind {
        case .door:
            var frame = Path()
            frame.move(to: CGPoint(x: 7, y: 20.5))
            frame.addLine(to: CGPoint(x: 7, y: 4.8))
            frame.addQuadCurve(to: CGPoint(x: 8.2, y: 3.5), control: CGPoint(x: 7, y: 3.5))
            frame.addLine(to: CGPoint(x: 15.8, y: 3.5))
            frame.addQuadCurve(to: CGPoint(x: 17, y: 4.8), control: CGPoint(x: 17, y: 3.5))
            frame.addLine(to: CGPoint(x: 17, y: 20.5))
            outline(frame, fill: Palette.paper, in: &context)
            var leaf = Path()
            leaf.addLines([CGPoint(x: 7, y: 20.5), CGPoint(x: 12.2, y: 18.9), CGPoint(x: 12.2, y: 5.3), CGPoint(x: 7, y: 3.9)])
            leaf.closeSubpath()
            outline(leaf, fill: Palette.moss, in: &context)
            context.fill(circle(10.6, 12.4, 0.9), with: .color(ink))
            var floor = Path()
            floor.move(to: CGPoint(x: 4, y: 20.5))
            floor.addLine(to: CGPoint(x: 20, y: 20.5))
            context.stroke(floor, with: .color(ink), style: line)
        case .flash:
            // Same disc as top and project, so the three results weigh the same.
            outline(circle(12, 12, 8.6), fill: Palette.coral, in: &context)
            var bolt = Path()
            bolt.addLines([CGPoint(x: 12.9, y: 6.9), CGPoint(x: 8.8, y: 12.7), CGPoint(x: 11.6, y: 12.7),
                           CGPoint(x: 10.9, y: 17.1), CGPoint(x: 15.2, y: 11.1), CGPoint(x: 12.4, y: 11.1)])
            bolt.closeSubpath()
            context.fill(bolt, with: .color(Palette.paper))
            context.stroke(bolt, with: .color(Palette.paper), style: StrokeStyle(lineWidth: 0.9, lineJoin: .round))
        case .top:
            outline(circle(12, 12, 8.6), fill: Palette.moss, in: &context)
            var check = Path()
            check.addLines([CGPoint(x: 8.2, y: 12.3), CGPoint(x: 10.8, y: 14.9), CGPoint(x: 15.8, y: 9.5)])
            context.stroke(check, with: .color(Palette.paper), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        case .project:
            context.fill(circle(12, 12, 8.6), with: .color(Palette.paper))
            context.fill(rightHalf(12, 12, 8.6), with: .color(Palette.plum))
            context.stroke(circle(12, 12, 8.6), with: .color(ink), style: line)
        case .chalkBag:
            // A floor bucket with chalk heaped over the rim.
            var heap = Path()
            heap.move(to: CGPoint(x: 7.4, y: 9))
            heap.addCurve(to: CGPoint(x: 11, y: 6.4), control1: CGPoint(x: 7.6, y: 6.6), control2: CGPoint(x: 9.4, y: 5.6))
            heap.addCurve(to: CGPoint(x: 15.4, y: 6.4), control1: CGPoint(x: 11.9, y: 4.9), control2: CGPoint(x: 14.3, y: 4.7))
            heap.addCurve(to: CGPoint(x: 16.6, y: 9), control1: CGPoint(x: 16.6, y: 6.6), control2: CGPoint(x: 17, y: 7.8))
            outline(heap, fill: Palette.paper, in: &context)
            var bag = Path()
            bag.move(to: CGPoint(x: 6.2, y: 9))
            bag.addLine(to: CGPoint(x: 17.8, y: 9))
            bag.addLine(to: CGPoint(x: 16.8, y: 19.1))
            bag.addQuadCurve(to: CGPoint(x: 14.8, y: 20.9), control: CGPoint(x: 16.6, y: 20.9))
            bag.addLine(to: CGPoint(x: 9.2, y: 20.9))
            bag.addQuadCurve(to: CGPoint(x: 7.2, y: 19.1), control: CGPoint(x: 7.4, y: 20.9))
            bag.closeSubpath()
            outline(bag, fill: Palette.mat, in: &context)
            var rim = Path()
            rim.move(to: CGPoint(x: 5.4, y: 9))
            rim.addLine(to: CGPoint(x: 18.6, y: 9))
            context.stroke(rim, with: .color(ink), style: line)
        case .lock:
            outline(Path(roundedRect: CGRect(x: 5.2, y: 10, width: 13.6, height: 10), cornerRadius: 2.4),
                    fill: Palette.mat, in: &context)
            var shackle = Path()
            shackle.move(to: CGPoint(x: 8.4, y: 10))
            shackle.addLine(to: CGPoint(x: 8.4, y: 7.4))
            shackle.addCurve(to: CGPoint(x: 15.6, y: 7.4), control1: CGPoint(x: 8.4, y: 2.6), control2: CGPoint(x: 15.6, y: 2.6))
            shackle.addLine(to: CGPoint(x: 15.6, y: 10))
            context.stroke(shackle, with: .color(ink), style: line)
            context.fill(circle(12, 14.3, 1.2), with: .color(ink))
            var keyhole = Path()
            keyhole.move(to: CGPoint(x: 12, y: 14.6))
            keyhole.addLine(to: CGPoint(x: 12, y: 16.8))
            context.stroke(keyhole, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        case .map:
            var sheet = Path()
            sheet.addLines([CGPoint(x: 3, y: 6), CGPoint(x: 9, y: 4), CGPoint(x: 15, y: 6), CGPoint(x: 21, y: 4),
                            CGPoint(x: 21, y: 18), CGPoint(x: 15, y: 20), CGPoint(x: 9, y: 18), CGPoint(x: 3, y: 20)])
            sheet.closeSubpath()
            context.fill(sheet, with: .color(Palette.mat))
            var middle = Path()
            middle.addLines([CGPoint(x: 9, y: 4), CGPoint(x: 15, y: 6), CGPoint(x: 15, y: 20), CGPoint(x: 9, y: 18)])
            middle.closeSubpath()
            context.fill(middle, with: .color(Palette.moss))
            context.stroke(sheet, with: .color(ink), style: line)
            var folds = Path()
            folds.move(to: CGPoint(x: 9, y: 4))
            folds.addLine(to: CGPoint(x: 9, y: 18))
            folds.move(to: CGPoint(x: 15, y: 6))
            folds.addLine(to: CGPoint(x: 15, y: 20))
            context.stroke(folds, with: .color(ink), style: line)
        case .filter:
            var funnel = Path()
            funnel.addLines([CGPoint(x: 4, y: 5), CGPoint(x: 20, y: 5), CGPoint(x: 14, y: 12.5), CGPoint(x: 14, y: 19),
                             CGPoint(x: 10, y: 21), CGPoint(x: 10, y: 12.5)])
            funnel.closeSubpath()
            outline(funnel, fill: Palette.mustard, in: &context)
        case .reset:
            // A mustard hold with one arrow turning around it. The arrow runs
            // clockwise from -38° to 248° as a fine polyline, so its direction
            // does not depend on how addArc reads "clockwise" with y down.
            var turn = Path()
            for step in 0...48 {
                let angle = (-38 + Double(step) * 286 / 48) * .pi / 180
                let point = CGPoint(x: 12 + 8.4 * cos(angle), y: 12 + 8.4 * sin(angle))
                if step == 0 { turn.move(to: point) } else { turn.addLine(to: point) }
            }
            turn.move(to: CGPoint(x: 5.94, y: 3.15))
            turn.addLines([CGPoint(x: 5.94, y: 3.15), CGPoint(x: 8.85, y: 4.21), CGPoint(x: 7.49, y: 7)])
            context.stroke(turn, with: .color(ink), style: line)
            var hold = Path()
            hold.move(to: CGPoint(x: 8.3, y: 15.9))
            hold.addCurve(to: CGPoint(x: 11.2, y: 9), control1: CGPoint(x: 7.3, y: 13.6), control2: CGPoint(x: 8.4, y: 10.2))
            hold.addCurve(to: CGPoint(x: 16.7, y: 11.8), control1: CGPoint(x: 13.9, y: 7.9), control2: CGPoint(x: 16.6, y: 9.1))
            hold.addCurve(to: CGPoint(x: 12.5, y: 16.8), control1: CGPoint(x: 16.8, y: 14.3), control2: CGPoint(x: 15, y: 16.3))
            hold.addCurve(to: CGPoint(x: 8.3, y: 15.9), control1: CGPoint(x: 10.6, y: 17.2), control2: CGPoint(x: 8.9, y: 17.1))
            hold.closeSubpath()
            outline(hold, fill: Palette.mustard, in: &context)
        }
    }
}
