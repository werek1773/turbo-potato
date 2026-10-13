import BoulderKit
import SwiftUI

/// Routesetter view of one sector photo: tap a hold to add a problem that
/// starts there (pick the grade, then optionally the rest of the route),
/// tap a pin to edit, move or take it down.
struct PinEditorView: View {
    let catalog: GymCatalog
    let sectorId: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var newPin: PendingPin?
    @State private var editing: ActiveProblem?
    @State private var moving: ActiveProblem?
    /// The last problem's grade and color, so a row of similar problems is fast.
    @State private var lastDraft = ProblemDraft()
    /// Holds on the photo: detected, or added by hand.
    @State private var holds: [PhotoHold] = []
    @State private var routeEditor: ActiveProblem?
    @State private var pendingRouteFor: UUID?
    @State private var pendingRouteEdit: ActiveProblem?
    @State private var isDetecting = false

    private var sector: Sector? { catalog.sectors.first { $0.id == sectorId } }

    var body: some View {
        NavigationStack {
            Group {
                if let sector, let photo = catalog.photo(of: sector) {
                    editor(sector: sector, photo: photo)
                } else {
                    ContentUnavailableView("Brak zdjęcia", systemImage: "camera",
                                           description: Text("Najpierw dodaj zdjęcie sektora."))
                }
            }
            .navigationTitle(sector?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
        }
        .sheet(item: $newPin, onDismiss: {
            // After saving, go straight on to the rest of the route.
            if let id = pendingRouteFor {
                pendingRouteFor = nil
                routeEditor = catalog.problems.first { $0.id == id }
            }
        }) { pin in
            ProblemEditorSheet(
                title: "Nowy problem",
                draft: pin.draft(from: lastDraft),
                grades: catalog.activeGrades,
                saveTitle: "Zapisz i dodaj chwyty"
            ) { draft in
                guard let sector, let photo = catalog.photo(of: sector) else { return false }
                do {
                    let start = try await startHold(for: pin, photo: photo, color: draft.color)
                    let id = try await catalog.addProblem(
                        to: sector,
                        at: CGPoint(x: start.x, y: start.y),
                        draft: draft,
                        route: [RouteStep(holdId: start.id, role: .start)]
                    )
                    lastDraft = ProblemDraft()
                    lastDraft.gradeId = draft.gradeId
                    lastDraft.color = draft.color
                    pendingRouteFor = id
                    return true
                } catch {
                    app.report(error)
                    return false
                }
            }
        }
        .fullScreenCover(item: $routeEditor) { problem in
            RouteEditorView(catalog: catalog, problem: problem)
        }
        .task(id: sector?.currentPhotoId) { await loadHolds() }
        .sheet(item: $editing, onDismiss: {
            if let problem = pendingRouteEdit {
                pendingRouteEdit = nil
                routeEditor = problem
            }
        }) { problem in
            ProblemEditorSheet(
                title: "Edytuj problem",
                draft: ProblemDraft(problem: problem),
                grades: catalog.activeGrades,
                onMove: { moving = problem },
                onEditRoute: { pendingRouteEdit = problem },
                onTakeDown: {
                    do {
                        try await catalog.takeDown(problem)
                        return true
                    } catch {
                        app.report(error)
                        return false
                    }
                }
            ) { draft in
                do {
                    try await catalog.updateProblem(problem, with: draft)
                    return true
                } catch {
                    app.report(error)
                    return false
                }
            }
        }
    }

    private func editor(sector: Sector, photo: SectorPhoto) -> some View {
        let problems = catalog.problems(in: sector)
        let grades = catalog.gradesById
        return VStack(spacing: 12) {
            Text(moving == nil
                 ? "Dotknij chwytu startowego, aby dodać problem. Dotknij pinezki, aby ją edytować."
                 : "Dotknij nowego miejsca dla pinezki.")
                .font(.footnote)
                .foregroundStyle(moving == nil ? Color.secondary : Palette.mossDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            AsyncImage(url: catalog.backend.photoURL(for: photo)) { phase in
                if case let .success(image) = phase {
                    image.resizable()
                } else {
                    Rectangle().fill(.quaternary).overlay(ProgressView())
                }
            }
            .aspectRatio(photo.aspectRatio, contentMode: .fit)
            .overlay {
                Canvas { context, size in
                    for hold in holds {
                        let radius = max(CGFloat(hold.r) * size.width * 1.2, 7)
                        let rect = CGRect(x: hold.x * size.width - radius, y: hold.y * size.height - radius,
                                          width: radius * 2, height: radius * 2)
                        context.stroke(Path(ellipseIn: rect), with: .color(Palette.paper.opacity(0.7)), lineWidth: 1.2)
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            let point = CGPoint(
                                x: min(max(location.x / proxy.size.width, 0), 1),
                                y: min(max(location.y / proxy.size.height, 0), 1)
                            )
                            handleTap(at: point, aspect: photo.aspectRatio)
                        }
                    ForEach(problems) { problem in
                        Button {
                            if moving == nil { editing = problem }
                        } label: {
                            ProblemPin(
                                color: problem.holdColor,
                                label: grades[problem.gradeId]?.label,
                                isHighlighted: moving == nil || moving?.id == problem.id
                            )
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: problem.pinX * proxy.size.width, y: problem.pinY * proxy.size.height)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            if moving != nil {
                Button("Anuluj przesuwanie") { moving = nil }
            }
            if holds.isEmpty {
                Button(isDetecting ? "Wykrywam chwyty…" : "Wykryj chwyty na zdjęciu", systemImage: "circle.dotted") {
                    Task { await detect(on: photo) }
                }
                .disabled(isDetecting)
            }
            Text("\(problems.count) problemów w sektorze")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func handleTap(at point: CGPoint, aspect: Double) {
        if let problem = moving {
            moving = nil
            Task {
                do { try await catalog.moveProblem(problem, to: point) } catch { app.report(error) }
            }
        } else {
            let hold = HoldMatching.hold(at: Double(point.x), Double(point.y), in: holds, aspect: aspect)
            newPin = PendingPin(point: point, hold: hold)
        }
    }

    /// The tapped hold, or a new one where the setter tapped.
    private func startHold(for pin: PendingPin, photo: SectorPhoto, color: HoldColor) async throws -> PhotoHold {
        if let hold = pin.hold { return hold }
        let hold = try await catalog.addHold(on: photo, x: Double(pin.point.x), y: Double(pin.point.y), color: color)
        holds.append(hold)
        return hold
    }

    private func loadHolds() async {
        guard let sector, let photo = catalog.photo(of: sector) else { return }
        do { holds = try await catalog.holds(on: photo) } catch { app.report(error) }
    }

    private func detect(on photo: SectorPhoto) async {
        isDetecting = true
        defer { isDetecting = false }
        do {
            try await catalog.detectHolds(on: photo)
            holds = try await catalog.holds(on: photo)
        } catch {
            app.report(error)
        }
    }
}

struct PendingPin: Identifiable {
    let id = UUID()
    let point: CGPoint
    /// The detected hold under the tap, if any: the problem starts there.
    var hold: PhotoHold?

    /// The form starts from the last problem's grade and color, or the
    /// tapped hold's color when it has one.
    func draft(from last: ProblemDraft) -> ProblemDraft {
        var draft = last
        if let color = hold?.color { draft.color = color }
        return draft
    }
}

/// Form sheet shared by "new problem" and "edit problem".
struct ProblemEditorSheet: View {
    let title: String
    let grades: [Grade]
    var onMove: (() -> Void)?
    var onEditRoute: (() -> Void)?
    var onTakeDown: (() async -> Bool)?
    var saveTitle = "Zapisz"
    /// Returns true when saved.
    let save: (ProblemDraft) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProblemDraft
    @State private var isWorking = false
    @State private var isConfirmingTakeDown = false

    init(
        title: String,
        draft: ProblemDraft,
        grades: [Grade],
        saveTitle: String = "Zapisz",
        onMove: (() -> Void)? = nil,
        onEditRoute: (() -> Void)? = nil,
        onTakeDown: (() async -> Bool)? = nil,
        save: @escaping (ProblemDraft) async -> Bool
    ) {
        self.title = title
        self.grades = grades
        self.saveTitle = saveTitle
        self.onMove = onMove
        self.onEditRoute = onEditRoute
        self.onTakeDown = onTakeDown
        self.save = save
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                ProblemForm(draft: $draft, grades: grades)
                if onMove != nil || onEditRoute != nil || onTakeDown != nil {
                    Section {
                        if let onEditRoute {
                            Button("Trasa: zaznacz chwyty", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                                onEditRoute()
                                dismiss()
                            }
                        }
                        if let onMove {
                            Button("Przesuń pinezkę", systemImage: "hand.point.up.left") {
                                onMove()
                                dismiss()
                            }
                        }
                        if onTakeDown != nil {
                            Button("Zdejmij problem", systemImage: "trash", role: .destructive) {
                                isConfirmingTakeDown = true
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button(saveTitle) { run { await save(draft) } }
                            .disabled(draft.gradeId == nil)
                    }
                }
            }
            .confirmationDialog("Zdjąć ten problem?", isPresented: $isConfirmingTakeDown, titleVisibility: .visible) {
                Button("Zdejmij", role: .destructive) {
                    if let onTakeDown { run { await onTakeDown() } }
                }
            } message: {
                Text("Problem zniknie z katalogu. Przejścia wspinaczy zostaną w ich dzienniku.")
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isWorking)
    }

    private func run(_ action: @escaping () async -> Bool) {
        isWorking = true
        Task {
            let done = await action()
            isWorking = false
            if done { dismiss() }
        }
    }
}
