import BoulderKit
import SwiftUI

/// Routesetter view of one sector photo: tap the wall to add a problem,
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
        .sheet(item: $newPin) { pin in
            ProblemEditorSheet(
                title: "Nowy problem",
                draft: lastDraft,
                grades: catalog.activeGrades
            ) { draft in
                guard let sector else { return false }
                do {
                    try await catalog.addProblem(to: sector, at: pin.point, draft: draft)
                    lastDraft = ProblemDraft()
                    lastDraft.gradeId = draft.gradeId
                    lastDraft.color = draft.color
                    return true
                } catch {
                    app.report(error)
                    return false
                }
            }
        }
        .sheet(item: $editing) { problem in
            ProblemEditorSheet(
                title: "Edytuj problem",
                draft: ProblemDraft(problem: problem),
                grades: catalog.activeGrades,
                onMove: { moving = problem },
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
                 ? "Dotknij ściany, aby dodać problem. Dotknij pinezki, aby ją edytować."
                 : "Dotknij nowego miejsca dla pinezki.")
                .font(.footnote)
                .foregroundStyle(moving == nil ? Color.secondary : Palette.olive)
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
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            let point = CGPoint(
                                x: min(max(location.x / proxy.size.width, 0), 1),
                                y: min(max(location.y / proxy.size.height, 0), 1)
                            )
                            handleTap(at: point)
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
            Text("\(problems.count) problemów w sektorze")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func handleTap(at point: CGPoint) {
        if let problem = moving {
            moving = nil
            Task {
                do { try await catalog.moveProblem(problem, to: point) } catch { app.report(error) }
            }
        } else {
            newPin = PendingPin(point: point)
        }
    }
}

struct PendingPin: Identifiable {
    let id = UUID()
    let point: CGPoint
}

/// Form sheet shared by "new problem" and "edit problem".
struct ProblemEditorSheet: View {
    let title: String
    let grades: [Grade]
    var onMove: (() -> Void)?
    var onTakeDown: (() async -> Bool)?
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
        onMove: (() -> Void)? = nil,
        onTakeDown: (() async -> Bool)? = nil,
        save: @escaping (ProblemDraft) async -> Bool
    ) {
        self.title = title
        self.grades = grades
        self.onMove = onMove
        self.onTakeDown = onTakeDown
        self.save = save
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                ProblemForm(draft: $draft, grades: grades)
                if onMove != nil || onTakeDown != nil {
                    Section {
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
                        Button("Zapisz") { run { await save(draft) } }
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
