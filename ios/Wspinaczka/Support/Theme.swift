import SwiftUI
import UIKit

// MARK: - Palette

/// Colors taken from the green room photo: chartreuse walls, mustard floor,
/// a plum chair and a coral vase, on a warm paper canvas.
enum Palette {
    static let canvas = Color(light: 0xF6F4EC, dark: 0x1C1C17)
    static let paper = Color(light: 0xFFFEF9, dark: 0x26261F)
    static let ink = Color(light: 0x23221C, dark: 0xEDEBE2)
    static let line = Color(light: 0xE3E0D2, dark: 0x3A3A30)
    /// The wall color of the photo; fills, the mark, walls on the map.
    static let chartreuse = Color(light: 0xB4B83A, dark: 0xC2C74A)
    /// Darker green that stays readable as text and tint.
    static let olive = Color(light: 0x6E7419, dark: 0xC8CD58)
    /// Matted floor on the map.
    static let mat = Color(light: 0xE9EBC6, dark: 0x33361C)
    static let mustard = Color(hex: 0xD6A12B)
    static let plum = Color(light: 0x5E2B4C, dark: 0xB07A9C)
    static let coral = Color(hex: 0xE2725B)
    static let door = Color(light: 0x3F9B55, dark: 0x5DBB72)
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Font {
    /// Serif display face (New York) for titles and greetings.
    static func serif(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif)
    }
}

// MARK: - Surfaces

extension View {
    /// Warm paper background behind scroll views and lists.
    func canvasBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Palette.canvas.ignoresSafeArea())
    }

    /// A card on the canvas: paper fill and a hairline edge.
    func paperCard(padding: CGFloat = 16, radius: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Palette.line))
    }
}

/// Full-width ink capsule, the main call to action.
struct PillButtonStyle: ButtonStyle {
    var isProminent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(isProminent ? Palette.canvas : Palette.ink)
            .background(isProminent ? Palette.ink : Palette.paper, in: Capsule())
            .overlay {
                if !isProminent { Capsule().stroke(Palette.line) }
            }
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillSecondary: PillButtonStyle { PillButtonStyle(isProminent: false) }
}

// MARK: - The mark: a climbing hold

/// A jug with its bolt hole, drawn in a 100×100 box.
struct HoldShape: Shape {
    var hasBoltHole = true

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 100 * rect.height)
        }
        var path = Path()
        path.move(to: p(22, 30))
        path.addCurve(to: p(74, 14), control1: p(30, 14), control2: p(56, 6))
        path.addCurve(to: p(88, 58), control1: p(90, 21), control2: p(95, 42))
        path.addCurve(to: p(46, 90), control1: p(82, 72), control2: p(66, 88))
        path.addCurve(to: p(9, 64), control1: p(28, 92), control2: p(12, 82))
        path.addCurve(to: p(22, 30), control1: p(7, 50), control2: p(14, 40))
        path.closeSubpath()
        if hasBoltHole {
            path.addEllipse(in: CGRect(origin: p(43, 41),
                                       size: CGSize(width: rect.width * 0.14, height: rect.height * 0.14)))
        }
        return path
    }
}

/// The lip of the jug, the edge you grab.
private struct HoldLip: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 100 * rect.height)
        }
        var path = Path()
        path.move(to: p(27, 35))
        path.addCurve(to: p(72, 26), control1: p(38, 24), control2: p(58, 20))
        return path
    }
}

/// The app's mark. It draws itself in on launch, breathes while idle and
/// swings like a loading spinner while work is in progress.
struct HoldMark: View {
    enum Motion {
        case still, drawIn, breathing, working
    }

    var motion: Motion = .still

    @State private var outline: CGFloat
    @State private var isFilled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(motion: Motion = .still) {
        self.motion = motion
        _outline = State(initialValue: motion == .drawIn ? 0 : 1)
        _isFilled = State(initialValue: motion != .drawIn)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.045
            ZStack {
                if motion == .drawIn {
                    HoldShape(hasBoltHole: false)
                        .trim(from: 0, to: outline)
                        .stroke(Palette.olive, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
                HoldShape()
                    .fill(Palette.chartreuse, style: FillStyle(eoFill: true))
                    .scaleEffect(isFilled ? 1 : 0.6)
                    .opacity(isFilled ? 1 : 0)
                HoldLip()
                    .trim(from: 0, to: isFilled ? 1 : 0)
                    .stroke(Palette.olive, style: StrokeStyle(lineWidth: width * 1.2, lineCap: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .modifier(MarkMotion(motion: reduceMotion ? .still : motion))
        .onAppear {
            guard motion == .drawIn else { return }
            if reduceMotion {
                outline = 1
                isFilled = true
                return
            }
            withAnimation(.easeOut(duration: 0.9)) { outline = 1 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.75)) { isFilled = true }
        }
        .accessibilityHidden(true)
    }
}

private struct MarkMotion: ViewModifier {
    let motion: HoldMark.Motion

    func body(content: Content) -> some View {
        switch motion {
        case .still, .drawIn:
            content
        case .breathing:
            content.phaseAnimator([false, true]) { view, phase in
                view
                    .rotationEffect(.degrees(phase ? 5 : -4), anchor: UnitPoint(x: 0.5, y: 0.6))
                    .scaleEffect(phase ? 1.06 : 1)
            } animation: { _ in
                .easeInOut(duration: 1.6)
            }
        case .working:
            content.keyframeAnimator(initialValue: 0.0, repeating: true) { view, angle in
                view.rotationEffect(.degrees(angle))
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(120, duration: 0.55, spring: .bouncy)
                    SpringKeyframe(240, duration: 0.55, spring: .bouncy)
                    SpringKeyframe(360, duration: 0.55, spring: .bouncy)
                }
            }
        }
    }
}

// MARK: - Entrances

private struct Rise: ViewModifier {
    let delay: Double
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .blur(radius: isShown || reduceMotion ? 0 : 8)
            .offset(y: isShown || reduceMotion ? 0 : 12)
            .onAppear {
                withAnimation(.smooth(duration: 0.7).delay(reduceMotion ? 0 : delay)) { isShown = true }
            }
    }
}

extension View {
    /// Fades in from a blur while rising a little, after `delay` seconds.
    func rise(_ delay: Double = 0) -> some View {
        modifier(Rise(delay: delay))
    }
}

/// Reveals text glyph by glyph out of a blur, like a voice starting to speak.
struct RevealRenderer: TextRenderer, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let slices: [Text.Layout.RunSlice] = layout.flatMap { line in line.flatMap { run in Array(run) } }
        let count = Double(slices.count)
        let spread = 8.0
        for (index, slice) in slices.enumerated() {
            let local = min(1, max(0, (progress * (count + spread) - Double(index)) / spread))
            var glyph = context
            glyph.opacity = local
            if local < 1 {
                glyph.addFilter(.blur(radius: (1 - local) * 5))
                glyph.translateBy(x: 0, y: (1 - local) * 6)
            }
            glyph.draw(slice)
        }
    }
}

struct RevealText: View {
    let text: Text
    var delay: Double = 0
    var duration: Double = 1.1

    @State private var progress = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ text: Text, delay: Double = 0, duration: Double = 1.1) {
        self.text = text
        self.delay = delay
        self.duration = duration
    }

    init(_ string: String, delay: Double = 0, duration: Double = 1.1) {
        self.init(Text(string), delay: delay, duration: duration)
    }

    var body: some View {
        text
            .textRenderer(RevealRenderer(progress: progress))
            .onAppear {
                if reduceMotion {
                    progress = 1
                } else {
                    withAnimation(.linear(duration: duration).delay(delay)) { progress = 1 }
                }
            }
    }
}

// MARK: - Greeting

enum Greeting {
    /// "Dobry wieczór, Rafał" — the default display name is left out.
    static func text(for name: String?, at date: Date = .now, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let opening = switch hour {
        case 5..<12: "Dzień dobry"
        case 12..<18: "Cześć"
        case 18..<23: "Dobry wieczór"
        default: "Nocna sesja?"
        }
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name != "Wspinacz",
              hour >= 5 && hour < 23 else { return opening }
        return "\(opening), \(name)"
    }
}
