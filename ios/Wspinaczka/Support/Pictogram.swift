import SwiftUI

/// The app's icons, drawn like the illustrations: a few loose ink lines over
/// one flat patch of color that does not quite fit the outline. On a 24×24
/// grid; the lines carry a fixed hand wobble (the same every time, no boil
/// at this size). Paths match the design mockup.
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

    private struct Drawing: Sendable {
        let color: Color
        let blob: InkPath
        let lines: [InkPath]
    }

    private static func drawing(_ kind: Kind) -> Drawing {
        switch kind {
        case .flash:
            Drawing(color: Palette.sun,
                    blob: InkPath("M5 12 C5 7 9 6 12 7 C16 8 17 12 16 16 C15 19 10 20 7 18 C5.5 17 5 14.5 5 12 Z"),
                    lines: [InkPath("M14.5 2.5 L8 12.5 L13 12.5 L9.5 21.5")])
        case .top:
            Drawing(color: Palette.sky,
                    blob: InkPath("M6 13 C6 8 9.5 5.5 13 6 C17 6.5 19.5 9.5 19 13.5 C18.5 17.5 15 19.5 11.5 19 C8 18.5 6 16.5 6 13 Z"),
                    lines: [InkPath("M4.5 12 C6.5 13.5 8 15.5 9.5 18.5 C12 12.5 15.5 8 20.5 4.5")])
        case .project:
            Drawing(color: Palette.plum,
                    blob: InkPath("M12 5 C16.5 5 19.5 8.5 19.5 13 C19.5 17 16.5 20 12.5 20 C12 15 12.2 10 12 5 Z"),
                    lines: [InkPath("M12 3.8 C17 3.8 20.3 7.5 20.3 12 C20.3 17 16.5 20.3 12 20.3 C7 20.3 3.8 16.5 3.8 12 C3.8 7.5 7 4.5 10.5 4")])
        case .door:
            Drawing(color: Palette.moss,
                    blob: InkPath("M8 7 C11 5 15.5 6 16.5 9 C17.5 13 17 18 14 19.5 C11 20.5 8.5 18.5 8 15 C7.5 12 7 9 8 7 Z"),
                    lines: [InkPath("M6 20.5 L6 4.5 C6 4 6.5 3.5 7 3.5 L16.5 3.5 C17 3.5 17.5 4 17.5 4.5 L17.5 20.5"),
                            InkPath("M3.5 20.8 C9 20.5 15 21 20.5 20.6"),
                            InkPath("M14 12 L14.2 12.3")])
        case .lock:
            Drawing(color: Palette.moss,
                    blob: InkPath("M7 14 C7 11.5 11 11 14 11.5 C17 12 19 13.5 18.5 16.5 C18 19.5 14 20.5 10.5 20 C8 19.5 7 17 7 14 Z"),
                    lines: [InkPath("M8.5 10.5 L8.5 7.5 C8.5 3.8 15.5 3.8 15.5 7.5 L15.5 10.5"),
                            InkPath("M5.2 10.5 C9.5 10.2 14.5 10.8 18.8 10.4 L18.2 20.3 C14 20.6 9.8 20.2 5.8 20.4 Z"),
                            InkPath("M12 14 L12 16.5")])
        case .reset:
            // A routesetter's cordless drill: what everyone pictures for a reset.
            Drawing(color: Palette.mustard,
                    blob: InkPath("M3 10.5 C4 8 9 7.8 12 9 C14.5 10.2 13.8 13.2 11 14.2 C8 15.2 4.5 14.8 3.5 13.3 C2.8 12.4 2.6 11.4 3 10.5 Z"),
                    lines: [InkPath("M3.6 6.8 L13.8 6.8 C14.8 6.8 15.4 7.4 15.4 8.4 L15.4 11.2 C15.4 12.2 14.8 12.8 13.8 12.8 L3.6 12.8 C2.9 12.8 2.4 12.3 2.4 11.6 L2.4 8 C2.4 7.3 2.9 6.8 3.6 6.8 Z"),
                            InkPath("M15.4 8.5 L17.8 8.5 L17.8 11.1 L15.4 11.1"),
                            InkPath("M17.8 9.8 L21.6 9.8"),
                            InkPath("M6.4 12.8 L5.6 18.6 L10.4 18.6 L10.8 12.8"),
                            InkPath("M4.6 18.6 L11.4 18.6 L11.4 21 L4.6 21 Z")])
        case .chalkBag:
            Drawing(color: Palette.coral,
                    blob: InkPath("M7.5 11 C7 15 7.5 19 10 20 C13 21 16 20 16.8 17.5 C17.5 15 17 12 16.5 10.5 C13 11.5 10 11.5 7.5 11 Z"),
                    lines: [InkPath("M6.8 9.5 C6.3 13.5 6.5 18 8 20 C10 21.3 14 21.3 16 20 C17.5 18 17.7 13.5 17.2 9.5"),
                            InkPath("M5.8 9.2 C8 7 16 7 18.2 9.2 C16 11.3 8 11.3 5.8 9.2 Z"),
                            InkPath("M10 4.5 L10.2 4.8"), InkPath("M13 3.2 L13.2 3.5"), InkPath("M15 5.2 L15.2 5.5")])
        case .map:
            Drawing(color: Palette.moss,
                    blob: InkPath("M6 9 C8 7 13 7 15 9 C17 11.5 16.5 16 13.5 17.5 C10.5 19 7 17.5 6 15 C5 13 4.8 10.5 6 9 Z"),
                    lines: [InkPath("M3 6.2 L9 4 L15 6.2 L21 4 L21 18 L15 20.2 L9 18 L3 20.2 Z"),
                            InkPath("M9 4 L9 18"), InkPath("M15 6.2 L15 20.2")])
        case .filter:
            Drawing(color: Palette.mustard,
                    blob: InkPath("M7 6 C10 5 15 5 17 6.5 C16 9 14 11 12.5 12 C11 11 8 8.5 7 6 Z"),
                    lines: [InkPath("M3.8 4.8 C9 4.4 15 5 20.2 4.6 L14 12.5 L14 19 L10 21 L10 12.5 Z")])
        }
    }

    static func draw(_ kind: Kind, in context: inout GraphicsContext) {
        let art = drawing(kind)
        context.fill(art.blob.path(frame: 0, boil: 0, salt: 0), with: .color(art.color))
        for (index, line) in art.lines.enumerated() {
            // Frame 0 with a fixed salt: a wobble that never changes.
            let path = line.path(frame: 0, boil: 0.7, salt: Double(index * 31 + 5))
            context.stroke(path, with: .color(Palette.ink),
                           style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }
    }
}
