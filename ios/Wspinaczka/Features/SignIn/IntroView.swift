import BoulderKit
import SwiftUI

/// First launch, before signing in: each page shows a real feature working,
/// and signing in comes last, once it is clear what you get.
struct IntroView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("hasSeenIntro") private var hasSeenIntro = false
    @State private var page = 0
    #if DEBUG
    @State private var isShowingTestSignIn = false
    #endif

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 16) {
            TabView(selection: $page) {
                FilterPage(isActive: page == 0).tag(0)
                SessionPage(isActive: page == 1).tag(1)
                ProgressPage(isActive: page == 2).tag(2)
                ReadyPage(isActive: page == 3).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.smooth, value: page)

            PageDots(count: pageCount, current: page)

            Group {
                if page < pageCount - 1 {
                    Button("Dalej") { withAnimation(.smooth) { page += 1 } }
                        .buttonStyle(.pill)
                } else {
                    VStack(spacing: 10) {
                        AppleSignInButton(label: .continue) { credential in
                            Task { await app.signIn(with: credential) }
                        } onError: { error in
                            app.report(error)
                        }
                        .clipShape(Capsule())
                        Text("Twoje przejścia widzisz tylko Ty.")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                        #if DEBUG
                        Button("Logowanie testowe") { isShowingTestSignIn = true }
                            .font(.footnote)
                        #endif
                    }
                    .transition(.opacity)
                }
            }
            .animation(.smooth, value: page == pageCount - 1)
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 12)
        .background(Palette.canvas.ignoresSafeArea())
        .onChange(of: page) { _, new in
            if new == pageCount - 1 { hasSeenIntro = true }
        }
        #if DEBUG
        .sheet(isPresented: $isShowingTestSignIn) {
            TestSignInView()
        }
        #endif
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Palette.moss : Palette.line)
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityHidden(true)
    }
}

/// Title (and a sentence) at the top of every intro page; the demo below is the picture.
private struct PageHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.display(.title))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pages

private struct FilterPage: View {
    let isActive: Bool
    @State private var grade: Int?

    var body: some View {
        VStack(spacing: 14) {
            PageHeader(title: "Chcesz same 4-ki? Jedno dotknięcie.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    GradeChip(label: "Wszystkie", isOn: grade == nil) { grade = nil }
                    ForEach(1...9, id: \.self) { value in
                        GradeChip(label: "\(value)", isOn: grade == value) { grade = value }
                    }
                }
            }
            .scrollClipDisabled()
            Spacer(minLength: 0)
            if isActive {
                DemoMap(grade: grade)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .task(id: isActive) {
            guard isActive else { return }
            grade = nil
            try? await Task.sleep(for: .seconds(2))
            grade = 4
        }
    }
}

private struct GradeChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 12)
                .frame(minWidth: 36, minHeight: 34)
                .foregroundStyle(isOn ? Palette.paper : Palette.ink)
                .background(isOn ? Palette.moss : Palette.paper, in: Capsule())
                .overlay(Capsule().stroke(isOn ? .clear : Palette.line))
        }
        .buttonStyle(.plain)
    }
}

private struct DemoMap: View {
    let grade: Int?
    @State private var selection: UUID?

    var body: some View {
        GymMapView(
            plan: IntroDemo.plan,
            sectors: IntroDemo.sectors,
            style: { _ in SectorMapStyle(color: Palette.moss) },
            dots: { IntroDemo.dots(for: $0, grade: grade) },
            selection: $selection
        )
    }
}

private struct SessionPage: View {
    let isActive: Bool

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(title: "Telefon zostaje w torbie.",
                       detail: "Po wyjściu stukasz w pinezki: raz top, dwa razy flash.")
            Spacer(minLength: 0)
            if isActive {
                TapDemo()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
    }
}

/// A finger taps pins on a wall photo, at 8 fps: hop, hop, tap, result.
private struct TapDemo: View {
    private struct Pin {
        let x: CGFloat, y: CGFloat
        let color: HoldColor
        let grade: String
    }

    private let pins = [Pin(x: 0.22, y: 0.62, color: .blue, grade: "3"),
                        Pin(x: 0.48, y: 0.32, color: .yellow, grade: "4"),
                        Pin(x: 0.76, y: 0.56, color: .red, grade: "5")]
    /// (pin, result, frame of the tap)
    private let script: [(Int, AscentResult, Int)] = [(0, .top, 6), (1, .top, 14), (1, .flash, 20), (2, .top, 28)]

    @State private var start = Date()

    var body: some View {
        TimelineView(.periodic(from: start, by: 1 / StopMotion.fps)) { timeline in
            let t = StopMotion.frame(at: timeline.date, since: start)
            let state = state(at: t)
            VStack(spacing: 14) {
                GeometryReader { proxy in
                    let size = proxy.size
                    ZStack {
                        WallPhotoBackdrop()
                        ForEach(pins.indices, id: \.self) { index in
                            ProblemPin(color: pins[index].color, label: pins[index].grade,
                                       isTopped: state.results[index] != nil, sessionResult: state.results[index])
                                .position(x: pins[index].x * size.width, y: pins[index].y * size.height)
                        }
                        if let finger = state.finger {
                            Circle()
                                .fill(.white.opacity(0.5))
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .frame(width: 36, height: 36)
                                .scaleEffect(state.isPressed ? 0.7 : 1)
                                .position(x: finger.x * size.width, y: finger.y * size.height)
                        }
                    }
                }
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 6) {
                    TallyChip(kind: .flash, label: "Flash", count: state.count(.flash))
                    TallyChip(kind: .top, label: "Top", count: state.count(.top))
                    TallyChip(kind: .project, label: "Projekt", count: 1)
                }
            }
        }
    }

    private struct DemoState {
        var results: [Int: AscentResult] = [:]
        var finger: CGPoint?
        var isPressed = false

        func count(_ result: AscentResult) -> Int { results.values.filter { $0 == result }.count }
    }

    private func state(at t: Int) -> DemoState {
        var state = DemoState()
        var previous = CGPoint(x: 0.5, y: 1.1)
        for (pinIndex, result, at) in script {
            let target = CGPoint(x: pins[pinIndex].x, y: pins[pinIndex].y)
            if t >= at - 3 && t < at {
                // Three hops towards the pin.
                let u = CGFloat(t - (at - 3) + 1) / 3
                state.finger = CGPoint(x: previous.x + (target.x - previous.x) * u, y: previous.y + (target.y - previous.y) * u)
            }
            if t == at {
                state.finger = target
                state.isPressed = true
            }
            if t > at {
                state.results[pinIndex] = result
                if state.finger == nil { state.finger = target }
            }
            previous = target
        }
        if t >= 34 { state.finger = nil }
        return state
    }
}

/// Stand-in for a sector photo: a wall with a few volumes.
private struct WallPhotoBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: [Color(light: 0xDCD8C8, dark: 0x3A3B33), Color(light: 0xC4BFA9, dark: 0x2C2D27)], startPoint: .topLeading, endPoint: .bottomTrailing)
                ForEach(Self.volumes.indices, id: \.self) { index in
                    let volume = Self.volumes[index]
                    Ellipse()
                        .fill(volume.color.opacity(0.5))
                        .frame(width: volume.w, height: volume.h)
                        .position(x: volume.x * size.width, y: volume.y * size.height)
                }
            }
        }
    }

    private struct Volume {
        let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
        let color: Color
    }

    private static let volumes = [
        Volume(x: 0.10, y: 0.18, w: 26, h: 18, color: Color(hex: 0xE46AA6)),
        Volume(x: 0.28, y: 0.80, w: 30, h: 20, color: Color(hex: 0x3E9A4C)),
        Volume(x: 0.58, y: 0.14, w: 24, h: 16, color: Color(hex: 0x8150C4)),
        Volume(x: 0.86, y: 0.30, w: 22, h: 18, color: Color(hex: 0xF08A24)),
        Volume(x: 0.40, y: 0.50, w: 36, h: 28, color: Color(hex: 0xA9A48F)),
        Volume(x: 0.66, y: 0.82, w: 26, h: 16, color: Color(hex: 0xE9C522)),
    ]
}

struct TallyChip: View {
    let kind: Pictogram.Kind
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Pictogram(kind: kind, size: 18)
            Text("\(label) \(count)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(Palette.paper, in: Capsule())
        .overlay(Capsule().stroke(Palette.line))
    }
}

private struct ProgressPage: View {
    let isActive: Bool

    private let levels = [(1, 6, 6), (2, 8, 7), (3, 11, 8), (4, 12, 6), (5, 10, 3), (6, 8, 1), (7, 5, 0)]
        .map { PyramidView.Level(label: "\($0.0)", active: $0.1, topped: $0.2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Twoja piramida",
                       detail: "Zrobione na każdej wycenie od ostatniej przykrętki.")
            Spacer(minLength: 0)
            if isActive {
                PyramidView(levels: levels)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Pictogram(kind: .lock, size: 22)
                Text("Widzisz ją tylko Ty.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
    }
}

private struct ReadyPage: View {
    let isActive: Bool

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            if isActive {
                DrawingView(drawing: .top)
                    .frame(height: 190)
            }
            Text("Gotowe do wspinania")
                .font(.display(.title))
                .foregroundStyle(Palette.ink)
            Text("Twoja ścianka już czeka.")
                .foregroundStyle(Palette.muted)
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}
