import SwiftUI
import UIKit

// MARK: - Palette

/// Colors of the green room photo: moss walls, a mustard floor, a plum chair
/// and a coral vase, on warm paper. In the dark the room is lit by a lamp:
/// near-black olive paper, cream ink, and the same colors a step brighter.
enum Palette {
    static let canvas = Color(light: 0xF7F5EE, dark: 0x191A15)
    static let paper = Color(light: 0xFFFEFA, dark: 0x23251E)
    /// Lines of the drawings and main text: dark ink by day, cream at night.
    static let ink = Color(light: 0x2A2A22, dark: 0xEDEADF)
    static let muted = Color(light: 0x6E6B5F, dark: 0xA29F92)
    static let line = Color(light: 0xE2DFD3, dark: 0x36382F)
    /// The wall color; buttons, walls on the map, selection.
    static let moss = Color(light: 0x6B8131, dark: 0x7F9839)
    /// Readable green for text and the pressed button: darker than moss by
    /// day, lighter at night.
    static let mossDark = Color(light: 0x4E5F22, dark: 0xA8C05A)
    static let mossLight = Color(light: 0x93A84B, dark: 0x93A84B)
    /// Matted floor on the map, empty bars.
    static let mat = Color(light: 0xE3E9CF, dark: 0x2C3322)
    static let mustard = Color(light: 0xD6A12B, dark: 0xD9A634)
    /// Mustard readable as text ("Przykrętka w czwartek").
    static let mustardText = Color(light: 0xA97C14, dark: 0xE2B44C)
    static let plum = Color(light: 0x6A3357, dark: 0xA0628C)
    static let coral = Color(light: 0xE2725B, dark: 0xE57B64)
    /// Top: a clear blue, the one cool color in the room.
    static let sky = Color(light: 0x3F7FBF, dark: 0x5592D0)
    /// Flash: sunny yellow, lighter than mustard so the two never mix up.
    static let sun = Color(light: 0xF2C12E, dark: 0xF2C12E)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// A color that follows the light or dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Appearance

/// Light, dark, or whatever the phone uses; chosen in the profile.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var polishName: String {
        switch self {
        case .system: "Systemowy"
        case .light: "Jasny"
        case .dark: "Ciemny"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Font {
    /// Wide, bold face for titles and numbers.
    static func display(_ style: Font.TextStyle) -> Font {
        .system(style, weight: .bold).width(.expanded)
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

/// Full-width moss capsule, the main call to action.
struct PillButtonStyle: ButtonStyle {
    var isProminent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(isProminent ? Palette.paper : Palette.ink)
            .background(isProminent ? (configuration.isPressed ? Palette.mossDark : Palette.moss) : Palette.paper,
                        in: Capsule())
            .overlay {
                if !isProminent { Capsule().stroke(Palette.line) }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillSecondary: PillButtonStyle { PillButtonStyle(isProminent: false) }
}

// MARK: - Entrances

private struct FadeUp: ViewModifier {
    let delay: Double
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45).delay(reduceMotion ? 0 : delay)) { isShown = true }
            }
    }
}

extension View {
    /// Fades in while rising a little, after `delay` seconds.
    func fadeUp(_ delay: Double = 0) -> some View {
        modifier(FadeUp(delay: delay))
    }
}

// MARK: - 8 fps clock

/// Illustrations move at 8 frames per second, like stop-motion: poses are
/// held and jump, lines wobble a little every frame. UI stays smooth.
enum StopMotion {
    static let fps = 8.0

    /// Frame number since `start`.
    static func frame(at date: Date, since start: Date) -> Int {
        max(0, Int(date.timeIntervalSince(start) * fps))
    }
}
