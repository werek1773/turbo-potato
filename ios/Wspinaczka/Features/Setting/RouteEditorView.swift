import BoulderKit
import SwiftUI

/// Staff build a problem's route by tapping holds on the sector photo.
/// A tap on a hold adds it; further taps make it a start, then the top,
/// then take it out. A tap where no hold was detected adds one there.
/// Holds of the problem's color stand out, so most taps are on them.
struct RouteEditorView: View {
    let catalog: GymCatalog
    let problem: ActiveProblem

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var holds: [PhotoHold] = []
    @State private var route: [RouteStep]
    @State private var zoom: CGFloat = 1
    @State private var isLoading = true
    @State private var isWorking = false

    init(catalog: GymCatalog, problem: ActiveProblem) {
        self.catalog = catalog
        self.problem = problem
        _route = State(initialValue: catalog.route(of: problem).map { RouteStep(holdId: $0.holdId, role: $0.role) })
    }

    private var photo: SectorPhoto? { catalog.photos[problem.photoId] }
    private var grade: String? { catalog.gradesById[problem.gradeId]?.label }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Stuknij chwyty trasy. Kolejne stuknięcie: start → top → usuń. Stuknięcie obok chwytu dodaje nowy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let photo {
                    GeometryReader { container in
                        ScrollView([.horizontal, .vertical]) {
                            editor(photo: photo, width: container.size.width * zoom)
                        }
                        .scrollIndicators(.hidden)
                    }
                } else {
                    ContentUnavailableView("Brak zdjęcia", systemImage: "camera")
                }

                HStack {
                    Picker("Powiększenie", selection: $zoom) {
                        Text("1×").tag(CGFloat(1))
                        Text("2×").tag(CGFloat(2))
                        Text("3×").tag(CGFloat(3))
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                    Spacer()
                    Text(summary)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(RouteBuilding.isValid(route) ? Color.secondary : Palette.coral)
                }
                .padding(.horizontal)

                if !isLoading, holds.isEmpty, let photo {
                    Button("Wykryj chwyty na zdjęciu", systemImage: "circle.dotted") {
                        Task { await detect(on: photo) }
                    }
                    .buttonStyle(.pillSecondary)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
            .navigationTitle("Trasa: \(problem.holdColor.polishName) \(grade ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Zapisz") { Task { await save() } }
                            .disabled(!RouteBuilding.isValid(route))
                    }
                }
            }
            .task { await loadHolds() }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private func editor(photo: SectorPhoto, width: CGFloat) -> some View {
        let height = width / photo.aspectRatio
        return AsyncImage(url: catalog.backend.photoURL(for: photo)) { phase in
            if case let .success(image) = phase {
                image.resizable()
            } else {
                Rectangle().fill(.quaternary).overlay(ProgressView())
            }
        }
        .frame(width: width, height: height)
        .overlay {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            tap(x: Double(location.x / width), y: Double(location.y / height), photo: photo)
        }
        .sensoryFeedback(.selection, trigger: route)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let roles = Dictionary(uniqueKeysWithValues: route.map { ($0.holdId, $0.role) })
        for hold in holds {
            let center = CGPoint(x: hold.x * size.width, y: hold.y * size.height)
            let radius = max(CGFloat(hold.r) * size.width * 1.2, 8)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            if let role = roles[hold.id] {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: -2.5, dy: -2.5)), with: .color(Palette.ink), lineWidth: 1.5)
                context.stroke(Path(ellipseIn: rect), with: .color(problem.holdColor.swatch), lineWidth: 4)
                if role != .hand {
                    let badge = role == .start ? "S" : "T"
                    let spot = CGPoint(x: rect.maxX - 2, y: rect.minY + 2)
                    context.fill(Path(ellipseIn: CGRect(x: spot.x - 9, y: spot.y - 9, width: 18, height: 18)), with: .color(Palette.ink))
                    context.draw(Text(badge).font(.caption2.bold()).foregroundStyle(Palette.paper), at: spot)
                }
            } else if hold.color == problem.holdColor {
                context.stroke(Path(ellipseIn: rect), with: .color(problem.holdColor.swatch.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            } else {
                context.stroke(Path(ellipseIn: rect), with: .color(Palette.paper.opacity(0.5)), lineWidth: 1)
            }
        }
    }

    private var summary: String {
        let starts = route.filter { $0.role == .start }.count
        let tops = route.filter { $0.role == .top }.count
        if route.isEmpty { return "Brak trasy" }
        if starts == 0 { return "Zaznacz start" }
        return "start \(starts) · chwyty \(route.count - starts - tops) · top \(tops)"
    }

    private func tap(x: Double, y: Double, photo: SectorPhoto) {
        if let hold = HoldMatching.hold(at: x, y, in: holds, aspect: photo.aspectRatio) {
            route = RouteBuilding.tapped(hold.id, in: route)
            return
        }
        Task {
            do {
                let hold = try await catalog.addHold(on: photo, x: x, y: y, color: problem.holdColor)
                holds.append(hold)
                route = RouteBuilding.tapped(hold.id, in: route)
            } catch {
                app.report(error)
            }
        }
    }

    private func loadHolds() async {
        defer { isLoading = false }
        guard let photo else { return }
        do { holds = try await catalog.holds(on: photo) } catch { app.report(error) }
    }

    private func detect(on photo: SectorPhoto) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await catalog.detectHolds(on: photo)
            holds = try await catalog.holds(on: photo)
        } catch {
            app.report(error)
        }
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await catalog.setRoute(of: problem, to: route)
            dismiss()
        } catch {
            app.report(error)
        }
    }
}
