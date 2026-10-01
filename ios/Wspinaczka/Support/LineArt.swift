import SwiftUI

// One-line ink drawings with a single flat color, redrawn at 8 fps: every
// frame each point moves a hair (line boil), and the splash draws itself on.
// Paths use the same absolute SVG syntax as the design mockup.

enum Wobble {
    static func noise(_ seed: Double) -> CGFloat {
        let x = sin(seed * 12.9898) * 43758.5453
        return CGFloat(x - floor(x))
    }
}

/// An absolute M/L/Q/C/Z path that can be redrawn with a little wobble.
struct InkPath: Sendable {
    private enum Segment: Sendable {
        case move(CGPoint), line(CGPoint), quad(CGPoint, CGPoint), cubic(CGPoint, CGPoint, CGPoint), close
    }

    private let segments: [Segment]

    init(_ d: String) {
        var tokens: [String] = []
        var current = ""
        for character in d {
            if character.isLetter {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(character))
            } else if character == " " || character == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if character == "-" && !current.isEmpty {
                tokens.append(current)
                current = "-"
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var index = 0
        func number() -> CGFloat {
            defer { index += 1 }
            return index < tokens.count ? CGFloat(Double(tokens[index]) ?? 0) : 0
        }
        func point() -> CGPoint {
            let x = number()
            let y = number()
            return CGPoint(x: x, y: y)
        }
        var parsed: [Segment] = []
        var command = "M"
        while index < tokens.count {
            if let first = tokens[index].first, first.isLetter {
                command = tokens[index]
                index += 1
                if command == "Z" || command == "z" {
                    parsed.append(.close)
                    continue
                }
            }
            switch command {
            case "M":
                parsed.append(.move(point()))
                command = "L"
            case "L":
                parsed.append(.line(point()))
            case "Q":
                let control = point()
                parsed.append(.quad(control, point()))
            case "C":
                let c1 = point()
                let c2 = point()
                parsed.append(.cubic(c1, c2, point()))
            default:
                index += 1
            }
        }
        segments = parsed
    }

    /// The path with every point nudged for this frame.
    func path(frame: Int, boil: CGFloat, salt: Double) -> Path {
        var i = 0.0
        func jitter(_ p: CGPoint) -> CGPoint {
            i += 1
            return CGPoint(x: p.x + (Wobble.noise(Double(frame) * 31 + i * 7 + salt) - 0.5) * boil,
                           y: p.y + (Wobble.noise(Double(frame) * 57 + i * 13 + salt) - 0.5) * boil)
        }
        var path = Path()
        for segment in segments {
            switch segment {
            case let .move(p): path.move(to: jitter(p))
            case let .line(p): path.addLine(to: jitter(p))
            case let .quad(c, p):
                let control = jitter(c)
                path.addQuadCurve(to: jitter(p), control: control)
            case let .cubic(c1, c2, p):
                let first = jitter(c1)
                let second = jitter(c2)
                path.addCurve(to: jitter(p), control1: first, control2: second)
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// The app's drawings.
enum Drawing: Sendable {
    /// A hand gripping a hold on the wall: launch, sign-in, loading.
    case grip
    /// A chalk bucket on a belt, chalk rising: empty states.
    case chalk
    /// A boulder with a flag on top: done, ready.
    case top

    struct Part: Sendable {
        enum Kind: Sendable {
            /// Ink line, drawn on in `steps` frames.
            case stroke(InkPath, steps: Int)
            /// Flat color shape; `alternate` swaps in every other two frames.
            case fill(InkPath, alternate: InkPath?, color: Color)
            case dots([CGPoint], radii: [CGFloat], inked: Bool)
            /// Chalk rising in a six-frame loop.
            case puff([CGPoint])
        }

        let kind: Kind
        /// Frame at which this part starts when drawing on.
        var at = 0
    }

    var parts: [Part] {
        switch self {
        case .grip: Self.gripParts
        case .chalk: Self.chalkParts
        case .top: Self.topParts
        }
    }

    /// Frames until the drawing-on finishes.
    var drawOnFrames: Int { self == .grip ? 13 : 0 }

    private static let gripParts: [Part] = [
        Part(kind: .fill(InkPath("M85 30 C70 26 52 32 50 44 C48 56 64 62 85 58 Z"), alternate: nil, color: Palette.moss), at: 9),
        Part(kind: .stroke(InkPath("M84 3 C86 26 81 60 85 97"), steps: 4), at: 0),
        Part(kind: .stroke(InkPath("M6 98 C20 84 30 72 40 60"), steps: 3), at: 3),
        Part(kind: .stroke(InkPath("M40 60 C42 48 46 38 54 32 C56 28 61 26 64 29 C66 25 71 25 73 29 C75 26 80 28 80 33 C81 38 79 42 76 42 C73 42 72 39 74 37"), steps: 4), at: 5),
        Part(kind: .stroke(InkPath("M24 100 C34 88 42 80 50 72"), steps: 3), at: 4),
        Part(kind: .stroke(InkPath("M50 72 C50 64 51 58 55 54 C49 54 45 50 46 46 C47 42 52 42 55 46"), steps: 3), at: 7),
        Part(kind: .dots([CGPoint(x: 34, y: 40), CGPoint(x: 28, y: 48), CGPoint(x: 40, y: 30), CGPoint(x: 31, y: 34)],
                         radii: [1.6, 1.1, 1.2, 0.9], inked: false), at: 11),
    ]

    private static let chalkParts: [Part] = [
        Part(kind: .fill(InkPath("M33 52 C32 66 33 78 37 83 C45 87 55 87 63 83 C67 78 68 66 67 52 C58 56 42 56 33 52 Z"), alternate: nil, color: Palette.mustard)),
        Part(kind: .fill(InkPath("M33 48 C40 44 60 44 67 48 C60 52 40 52 33 48 Z"), alternate: nil, color: Color(hex: 0xF1EEDF))),
        Part(kind: .stroke(InkPath("M31 49 C30 64 31 79 35 85 C44 90 56 90 65 85 C69 79 70 64 69 49"), steps: 1)),
        Part(kind: .stroke(InkPath("M30 48 C38 42 62 42 70 48 C62 54 38 54 30 48 Z"), steps: 1)),
        Part(kind: .stroke(InkPath("M12 66 C28 70 72 70 88 66"), steps: 1)),
        Part(kind: .stroke(InkPath("M64 52 C67 57 65 60 68 63"), steps: 1)),
        Part(kind: .puff([CGPoint(x: 44, y: 34), CGPoint(x: 52, y: 28), CGPoint(x: 58, y: 35),
                          CGPoint(x: 48, y: 22), CGPoint(x: 40, y: 26), CGPoint(x: 60, y: 24)])),
    ]

    private static let topParts: [Part] = [
        Part(kind: .fill(InkPath("M47 12 C55 9 63 15 70 12 C68 18 68 22 70 27 C63 30 55 24 47 27 Z"),
                         alternate: InkPath("M47 12 C55 15 61 9 70 14 C67 19 69 23 69 28 C62 25 55 30 47 27 Z"),
                         color: Palette.coral)),
        Part(kind: .stroke(InkPath("M6 87 C30 86 70 88 94 86"), steps: 1)),
        Part(kind: .stroke(InkPath("M12 87 C12 74 16 62 24 56 L34 45 C40 38 50 37 56 41 L70 51 C80 57 88 70 88 87"), steps: 1)),
        Part(kind: .stroke(InkPath("M47 39 C46 29 48 20 47 10"), steps: 1)),
        Part(kind: .stroke(InkPath("M60 68 L66 62 L70 66"), steps: 1)),
    ]

    private static let dust = Color(hex: 0xCFCAB8)
    private static let chalk = Color(hex: 0xD8D4C4)

    /// Draws one frame. `progress` counts frames since drawing-on began.
    func draw(frame: Int, progress: Int, boil: CGFloat, in context: inout GraphicsContext) {
        for (index, part) in parts.enumerated() {
            let local = progress - part.at
            guard local >= 0 else { continue }
            let salt = Double(index * 101)
            switch part.kind {
            case let .fill(shape, alternate, color):
                let source = alternate != nil && frame % 4 >= 2 ? alternate! : shape
                var path = source.path(frame: frame, boil: boil * 0.8, salt: salt)
                // Pops in over two frames: small, a bit too big, settled.
                let scale: CGFloat = local < 1 ? 0.7 : (local < 2 ? 1.08 : 1)
                if scale != 1 {
                    let center = CGPoint(x: path.boundingRect.midX, y: path.boundingRect.midY)
                    path = path.applying(CGAffineTransform(translationX: center.x, y: center.y)
                        .scaledBy(x: scale, y: scale)
                        .translatedBy(x: -center.x, y: -center.y))
                }
                context.fill(path, with: .color(color))
            case let .stroke(shape, steps):
                let shown = min(1, CGFloat(local + 1) / CGFloat(steps))
                let path = shape.path(frame: frame, boil: boil, salt: salt).trimmedPath(from: 0, to: shown)
                context.stroke(path, with: .color(Palette.ink),
                               style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            case let .dots(points, radii, inked):
                for (j, point) in points.enumerated() where Double(local) >= Double(j) * 0.5 {
                    let x = point.x + (Wobble.noise(Double(frame + j)) - 0.5) * 0.8
                    let y = point.y + (Wobble.noise(Double(frame * 3 + j)) - 0.5) * 0.8
                    let r = radii[j]
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(inked ? Palette.ink : Self.dust))
                }
            case let .puff(points):
                for (j, point) in points.enumerated() {
                    let t = (frame + j * 2) % 6
                    guard t <= 4 else { continue }
                    let cycle = Double((frame + j * 2) / 6)
                    let x = point.x + (Wobble.noise(Double(j * 9) + cycle) - 0.5) * 6
                    let y = point.y + 8 - CGFloat(t) * 3
                    let r = 1.2 + CGFloat(t) * 0.5
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(Self.chalk.opacity(1 - Double(t) * 0.2)))
                }
            }
        }
    }
}

/// A drawing on the 8 fps clock. With `drawsOn`, it draws itself first.
struct DrawingView: View {
    let drawing: Drawing
    var drawsOn = false

    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: start, by: 1 / StopMotion.fps)) { timeline in
            let frame = reduceMotion ? 0 : StopMotion.frame(at: timeline.date, since: start)
            let progress = drawsOn && !reduceMotion ? frame : 1000
            Canvas { context, size in
                let scale = min(size.width, size.height) / 100
                context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                drawing.draw(frame: frame, progress: progress, boil: reduceMotion ? 0 : 0.9, in: &context)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A grade pyramid drawn in ink: one band per grade, narrowing upwards, the
/// done part filled with moss. Builds bottom-up on the 8 fps clock.
struct PyramidView: View {
    struct Level: Hashable, Sendable {
        let label: String
        let active: Int
        let topped: Int
    }

    let levels: [Level]

    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: start, by: 1 / StopMotion.fps)) { timeline in
            let frame = reduceMotion ? 0 : StopMotion.frame(at: timeline.date, since: start)
            let built = reduceMotion ? 1000 : frame - 2
            Canvas { context, size in
                let scale = min(size.width / 100, size.height / 92)
                context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 92 * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                draw(frame: frame, built: built, in: &context)
            }
        }
        .aspectRatio(100 / 92, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(levels.map { "\($0.label): \($0.topped) z \($0.active)" }.joined(separator: ", "))
    }

    private func draw(frame: Int, built: Int, in context: inout GraphicsContext) {
        let rowHeight: CGFloat = 10, gap: CGFloat = 2.6
        for (k, level) in levels.enumerated() {
            let local = built - k * 2
            guard local >= 0 else { continue }
            let width = max(66 - CGFloat(k) * 7.5, 12)
            let x0 = 50 - width / 2
            let y1 = 88 - CGFloat(k) * (rowHeight + gap)
            let y0 = y1 - rowHeight
            let done = level.active > 0 ? width * CGFloat(level.topped) / CGFloat(level.active) : 0
            if done > 0 && local >= 1 {
                let fill = InkPath("M\(x0) \(y0) L\(x0 + done) \(y0) L\(x0 + done) \(y1) L\(x0) \(y1) Z")
                context.fill(fill.path(frame: frame, boil: 0.6, salt: Double(k * 17 + 5)), with: .color(Palette.moss))
            }
            let box = InkPath("M\(x0) \(y0) L\(x0 + width) \(y0) L\(x0 + width) \(y1) L\(x0) \(y1) Z")
            context.stroke(box.path(frame: frame, boil: 0.7, salt: Double(k * 17)), with: .color(Palette.ink),
                           style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
            context.draw(Text(level.label).font(.system(size: 6.4, weight: .heavy, design: .rounded)).foregroundStyle(Palette.ink),
                         at: CGPoint(x: x0 - 3, y: y0 + rowHeight / 2), anchor: .trailing)
            context.draw(Text("\(level.topped)/\(level.active)").font(.system(size: 5)).foregroundStyle(Palette.muted),
                         at: CGPoint(x: x0 + width + 3, y: y0 + rowHeight / 2), anchor: .leading)
        }
    }
}
