import BoulderKit
import PhotosUI
import SwiftUI

/// New sector photo: the first photo of a sector or a reset ("przykrętka").
/// The setter picks which of the current problems come down.
struct NewSectorPhotoView: View {
    let catalog: GymCatalog
    let sector: Sector
    /// Called after a successful upload, e.g. to open the pin editor.
    let onPublished: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isShowingCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var removing: Set<UUID> = []
    @State private var note = ""
    @State private var isSaving = false

    private var problems: [ActiveProblem] { catalog.problems(in: sector) }
    private var grades: [UUID: Grade] { catalog.gradesById }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if CameraPicker.isAvailable {
                        Button(image == nil ? "Zrób zdjęcie" : "Zrób jeszcze raz", systemImage: "camera") {
                            isShowingCamera = true
                        }
                    }
                    PhotosPicker(selection: $libraryItem, matching: .images) {
                        Label("Wybierz z galerii", systemImage: "photo.on.rectangle")
                    }
                } footer: {
                    Text("Zrób zdjęcie całego sektora na wprost, z daleka i bez ludzi na ścianie.")
                }

                if !problems.isEmpty {
                    Section {
                        ForEach(problems) { problem in
                            Toggle(isOn: Binding(
                                get: { removing.contains(problem.id) },
                                set: { isOn in
                                    if isOn { removing.insert(problem.id) } else { removing.remove(problem.id) }
                                }
                            )) {
                                HStack {
                                    ProblemPin(color: problem.holdColor, label: grades[problem.gradeId]?.label)
                                    Text(problem.name ?? grades[problem.gradeId].map { "Problem \($0.label)" } ?? "Problem")
                                }
                            }
                        }
                    } header: {
                        Text("Zdejmowane problemy")
                    } footer: {
                        Text("Zaznaczone znikną z katalogu i trafią do archiwum przykrętek. Pozostałe przejdą na nowe zdjęcie — ich pinezki można potem poprawić.")
                    }

                    Section {
                        TextField("Notatka, np. Nowe struktury", text: $note)
                    }
                }
            }
            .navigationTitle(problems.isEmpty ? "Zdjęcie sektora" : "Przykrętka: \(sector.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Zapisz") { Task { await save() } }
                            .disabled(image == nil)
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker { image = $0 }
                    .ignoresSafeArea()
            }
            .onChange(of: libraryItem) { _, item in
                Task { await loadLibraryImage(item) }
            }
            .onAppear {
                // A reset usually takes everything down.
                removing = Set(problems.map(\.id))
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func loadLibraryImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                image = picked
            }
        } catch {
            app.report(error)
        }
    }

    private func save() async {
        guard let image else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await catalog.publishPhoto(image, for: sector, removing: removing, note: note)
            dismiss()
            onPublished()
        } catch {
            app.report(error)
        }
    }
}
