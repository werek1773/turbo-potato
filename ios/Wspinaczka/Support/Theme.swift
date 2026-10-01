import SwiftUI
import UIKit

// MARK: - Palette

/// Colors of the green room photo: moss walls, a mustard floor, a plum chair
/// and a coral vase, on warm paper. The app is light only.
enum Palette {
    static let canvas = Color(hex: 0xF7F5EE)
    static let paper = Color(hex: 0xFFFEFA)
    static let ink = Color(hex: 0x2A2A22)
    static let muted = Color(hex: 0x6E6B5F)
    static let line = Color(hex: 0xE2DFD3)
    /// The wall color; buttons, walls on the map, selection.
    static let moss = Color(hex: 0x6B8131)
    /// Readable green for text and the selected wall.
    static let mossDark = Color(hex: 0x4E5F22)
    static let mossLight = Color(hex: 0x93A84B)
    /// Matted floor on the map, empty bars.
    static let mat = Color(hex: 0xE3E9CF)
    static let mustard = Color(hex: 0xD6A12B)
    /// Mustard dark enough for text ("Przykrętka w czwartek").
    static let mustardText = Color(hex: 0xA97C14)
    static let plum = Color(hex: 0x6A3357)
    static let coral = Color(hex: 0xE2725B)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    /// Rounded, bold face for titles and numbers: soft ends like the ink
    /// line of the drawings and the holds themselves.
    static func display(_ style: Font.TextStyle) -> Font {
        .system(style, design: .rounded, weight: .bold)
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

    /// Small uppercase label above a title ("PO SESJI").
    func eyebrow() -> some View {
        font(.caption.weight(.bold))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Palette.mossDark)
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
