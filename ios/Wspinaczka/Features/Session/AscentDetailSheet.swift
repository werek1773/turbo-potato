import BoulderKit
import SwiftUI

/// Details of one problem in the session: result, attempts, how it felt and,
/// for projects, what stopped me.
struct AscentDetailSheet: View {
    let log: SessionLog
    let problem: ActiveProblem

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var result: AscentResult
    @State private var attempts: AttemptsBucket?
    @State private var perceived: PerceivedGrade?
    @State private var limiters: Set<Limiter>
    @State private var note: String
    @State private var isSaving = false

    init(log: SessionLog, problem: ActiveProblem) {
        self.log = log
        self.problem = problem
        let current = log.results[problem.id]
        _result = State(initialValue: current?.result ?? .top)
        _attempts = State(initialValue: current?.attempts)
        _perceived = State(initialValue: current?.perceivedGrade)
        _limiters = State(initialValue: Set(current?.limiters ?? []))
        _note = State(initialValue: current?.note ?? "")
    }

    private var canFlash: Bool { log.flashable.contains(problem.id) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Wynik", selection: $result) {
                        ForEach(AscentResult.allCases.filter { $0 != .flash || canFlash }, id: \.self) { value in
                            Label(value.polishName, systemImage: value.symbol).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if !canFlash {
                        Text("Flash jest możliwy tylko, jeśli to Twoja pierwsza próba tego problemu.")
                    }
                }

                if result != .flash {
                    Section("Ile prób (mniej więcej)") {
                        Picker("Próby", selection: $attempts) {
                            Text("—").tag(AttemptsBucket?.none)
                            ForEach(AttemptsBucket.allCases, id: \.self) { value in
                                Text(value.polishName).tag(Optional(value))
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Wycena według Ciebie") {
                    Picker("Wycena", selection: $perceived) {
                        Text("—").tag(PerceivedGrade?.none)
                        ForEach(PerceivedGrade.allCases, id: \.self) { value in
                            Text(value.polishName).tag(Optional(value))
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if result == .project {
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                            ForEach(Limiter.allCases, id: \.self) { limiter in
                                let selected = limiters.contains(limiter)
                                Button {
                                    if selected {
                                        limiters.remove(limiter)
                                    } else if limiters.count < 5 {
                                        limiters.insert(limiter)
                                    }
                                } label: {
                                    Text(limiter.polishName)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, minHeight: 34)
                                        .background(selected ? Palette.chartreuse.opacity(0.3) : Color.secondary.opacity(0.1),
                                                    in: Capsule())
                                        .overlay(Capsule().stroke(selected ? Palette.olive : .clear, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Co Cię zatrzymało?")
                    } footer: {
                        Text("Z tych odpowiedzi powstaje Twój profil słabych stron. Ścianka widzi je tylko zbiorczo i anonimowo.")
                    }
                }

                Section("Notatka") {
                    TextField("np. beta: lewa noga wysoko", text: $note, axis: .vertical)
                }

                if log.results[problem.id] != nil {
                    Section {
                        Button("Usuń z tej sesji", role: .destructive) {
                            run { try await log.set(problem, result: nil) }
                        }
                    }
                }
            }
            .navigationTitle("Szczegóły")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Zapisz") {
                            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                            run {
                                try await log.set(
                                    problem,
                                    result: result,
                                    attempts: attempts,
                                    perceivedGrade: perceived,
                                    limiters: Array(limiters),
                                    note: trimmed.isEmpty ? nil : trimmed
                                )
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await action()
                dismiss()
            } catch {
                app.report(error)
            }
        }
    }
}
