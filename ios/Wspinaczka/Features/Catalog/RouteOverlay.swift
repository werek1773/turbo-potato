import BoulderKit
import SwiftUI

/// Hold geometry on a photo of `size`: centre in points and radius in
/// points (a hold's radius is a share of the photo's width).
private func circle(x: Double, y: Double, r: Double, in size: CGSize, grow: CGFloat) -> CGRect {
    let center = CGPoint(x: x * size.width, y: y * size.height)
    let radius = max(CGFloat(r) * size.width * grow, 9)
    return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

/// A colored ring with an ink edge, as everything in the app is inked.
private func ring(_ rect: CGRect, color: Color, width: CGFloat, in context: inout GraphicsContext) {
    context.stroke(Path(ellipseIn: rect.insetBy(dx: -width / 2 - 0.75, dy: -width / 2 - 0.75)),
                   with: .color(Palette.ink.opacity(0.8)), lineWidth: 1.5)
    context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: width)
}

/// Start marks: two short strokes under the hold, like tape on the wall.
/// Not a circle or a diamond: those mean top and flash in a session.
private func startMarks(below rect: CGRect, in context: inout GraphicsContext) {
    var marks = Path()
    for dx: CGFloat in [-4, 4] {
        marks.move(to: CGPoint(x: rect.midX + dx - 1.5, y: rect.maxY + 4))
        marks.addLine(to: CGPoint(x: rect.midX + dx + 1.5, y: rect.maxY + 11))
    }
    context.stroke(marks, with: .color(Palette.paper), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
    context.stroke(marks, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
}

/// Top: a small flag on the hold's upper right, as in the "top" drawing.
private func topFlag(on rect: CGRect, color: Color, in context: inout GraphicsContext) {
    let foot = CGPoint(x: rect.midX + rect.width * 0.32, y: rect.midY - rect.height * 0.32)
    let head = CGPoint(x: foot.x + 2, y: foot.y - 18)
    var flag = Path()
    flag.move(to: head)
    flag.addLine(to: CGPoint(x: head.x + 11, y: head.y + 4))
    flag.addLine(to: CGPoint(x: head.x + 1, y: head.y + 8))
    flag.closeSubpath()
    var pole = Path()
    pole.move(to: foot)
    pole.addLine(to: head)
    context.stroke(pole, with: .color(Palette.paper), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
    context.stroke(pole, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    context.fill(flag, with: .color(color))
    context.stroke(flag, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
}

/// The chosen problem's route on its photo: the rest of the wall dimmed,
/// its holds lit and ringed in the route's color, start and top marked.
struct RouteOverlay: View {
    let route: [RouteHold]
    let color: HoldColor

    var body: some View {
        Canvas { context, size in
            context.drawLayer { layer in
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.ink.opacity(0.55)))
                layer.blendMode = .destinationOut
                for hold in route {
                    layer.fill(Path(ellipseIn: circle(x: hold.x, y: hold.y, r: hold.r, in: size, grow: 1.35)),
                               with: .color(.black))
                }
            }
            for hold in route {
                let rect = circle(x: hold.x, y: hold.y, r: hold.r, in: size, grow: 1.35)
                ring(rect, color: color.swatch, width: hold.role == .hand ? 2.5 : 4, in: &context)
                switch hold.role {
                case .start: startMarks(below: rect, in: &context)
                case .top: topFlag(on: rect, color: color.swatch, in: &context)
                case .hand: break
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// On the plain photo: a ring around every problem's start hold, so the
/// start is visible before anything is tapped.
struct StartRings: View {
    struct Item: Hashable {
        let hold: RouteHold
        let color: HoldColor
        let isHighlighted: Bool
    }

    let items: [Item]

    var body: some View {
        Canvas { context, size in
            for item in items {
                let rect = circle(x: item.hold.x, y: item.hold.y, r: item.hold.r, in: size, grow: 1.25)
                var inner = context
                inner.opacity = item.isHighlighted ? 1 : 0.25
                ring(rect, color: item.color.swatch, width: 3, in: &inner)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Where a problem's grade tag goes: beside its start hold (lower right,
/// clear of the hold), or on the pin when it has no route.
enum TagPlacement {
    static func point(for problem: ActiveProblem, route: [RouteHold], in size: CGSize) -> CGPoint {
        let starts = route.filter { $0.role == .start }
        guard !starts.isEmpty else {
            return CGPoint(x: problem.pinX * size.width, y: problem.pinY * size.height)
        }
        let x = starts.map(\.x).reduce(0, +) / Double(starts.count)
        let y = starts.map(\.y).reduce(0, +) / Double(starts.count)
        let radius = max(starts.map(\.r).max() ?? 0, 0) * size.width * 1.25
        let reach = radius * 0.75 + 15
        var point = CGPoint(x: x * size.width + reach, y: y * size.height + reach)
        // Keep the tag on the photo: flip to the other side at an edge.
        if point.x > size.width - 14 { point.x = x * size.width - reach }
        if point.y > size.height - 14 { point.y = y * size.height - reach }
        return point
    }
}
