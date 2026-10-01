import SwiftUI

/// The app's drawn icons: one hand, a rounded ink line and flat fills from
/// the palette, on a 24×24 grid.
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
            outline(frame, fill: Palette.mossLight, in: &context)
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
            var bolt = Path()
            bolt.addLines([CGPoint(x: 13.4, y: 2.8), CGPoint(x: 5.8, y: 13.2), CGPoint(x: 10.9, y: 13.2),
                           CGPoint(x: 9.7, y: 21.2), CGPoint(x: 17.6, y: 10.3), CGPoint(x: 12.4, y: 10.3)])
            bolt.closeSubpath()
            outline(bolt, fill: Palette.coral, in: &context)
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
            var bag = Path()
            bag.move(to: CGPoint(x: 6.2, y: 8.6))
            bag.addLine(to: CGPoint(x: 17.8, y: 8.6))
            bag.addLine(to: CGPoint(x: 16.8, y: 18.7))
            bag.addQuadCurve(to: CGPoint(x: 14.8, y: 20.5), control: CGPoint(x: 16.6, y: 20.5))
            bag.addLine(to: CGPoint(x: 9.2, y: 20.5))
            bag.addQuadCurve(to: CGPoint(x: 7.2, y: 18.7), control: CGPoint(x: 7.4, y: 20.5))
            bag.closeSubpath()
            outline(bag, fill: Palette.mustard, in: &context)
            var rim = Path()
            rim.move(to: CGPoint(x: 5.4, y: 8.6))
            rim.addLine(to: CGPoint(x: 18.6, y: 8.6))
            context.stroke(rim, with: .color(ink), style: line)
            for (x, y, r) in [(9.4, 5.2, 1.4), (12.6, 4.0, 1.1), (14.9, 6.0, 1.3)] as [(CGFloat, CGFloat, CGFloat)] {
                context.fill(circle(x, y, r), with: .color(Palette.line))
            }
        case .lock:
            outline(Path(roundedRect: CGRect(x: 5.2, y: 10.4, width: 13.6, height: 10), cornerRadius: 2.4),
                    fill: Palette.moss, in: &context)
            var shackle = Path()
            shackle.move(to: CGPoint(x: 8.4, y: 10.4))
            shackle.addLine(to: CGPoint(x: 8.4, y: 7.6))
            shackle.addCurve(to: CGPoint(x: 15.6, y: 7.6), control1: CGPoint(x: 8.4, y: 2.8), control2: CGPoint(x: 15.6, y: 2.8))
            shackle.addLine(to: CGPoint(x: 15.6, y: 10.4))
            context.stroke(shackle, with: .color(ink), style: line)
            var keyhole = Path()
            keyhole.move(to: CGPoint(x: 12, y: 14.2))
            keyhole.addLine(to: CGPoint(x: 12, y: 16.6))
            context.stroke(keyhole, with: .color(Palette.paper), style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
            var upper = Path()
            upper.move(to: CGPoint(x: 18.6, y: 9.2))
            upper.addQuadCurve(to: CGPoint(x: 5.4, y: 8.4), control: CGPoint(x: 12, y: 1.5))
            var lower = Path()
            lower.move(to: CGPoint(x: 5.4, y: 14.8))
            lower.addQuadCurve(to: CGPoint(x: 18.6, y: 15.6), control: CGPoint(x: 12, y: 22.5))
            var arrows = Path()
            arrows.addLines([CGPoint(x: 18.9, y: 4.6), CGPoint(x: 18.9, y: 9.4), CGPoint(x: 14.1, y: 9.4)])
            arrows.move(to: CGPoint(x: 5.1, y: 19.4))
            arrows.addLines([CGPoint(x: 5.1, y: 19.4), CGPoint(x: 5.1, y: 14.6), CGPoint(x: 9.9, y: 14.6)])
            for path in [upper, lower, arrows] {
                context.stroke(path, with: .color(ink), style: line)
            }
            context.fill(circle(12, 12, 2.4), with: .color(Palette.mustard))
            context.stroke(circle(12, 12, 2.4), with: .color(ink), lineWidth: 1.4)
        }
    }
}

/// An entrance on the map: a dark moss disc with a door.
struct DoorMarker: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 8
            context.scaleBy(x: s, y: s)
            context.fill(Path(ellipseIn: CGRect(x: 0.4, y: 0.4, width: 7.2, height: 7.2)), with: .color(Palette.mossDark))
            var door = Path()
            door.move(to: CGPoint(x: 2.7, y: 5.9))
            door.addLine(to: CGPoint(x: 2.7, y: 2.4))
            door.addQuadCurve(to: CGPoint(x: 3.2, y: 1.9), control: CGPoint(x: 2.7, y: 1.9))
            door.addLine(to: CGPoint(x: 4.8, y: 1.9))
            door.addQuadCurve(to: CGPoint(x: 5.3, y: 2.4), control: CGPoint(x: 5.3, y: 1.9))
            door.addLine(to: CGPoint(x: 5.3, y: 5.9))
            door.move(to: CGPoint(x: 1.9, y: 5.9))
            door.addLine(to: CGPoint(x: 6.1, y: 5.9))
            context.stroke(door, with: .color(Palette.paper), style: StrokeStyle(lineWidth: 0.65, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("Wejście")
    }
}
