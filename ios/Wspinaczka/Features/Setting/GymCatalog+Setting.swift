import BoulderKit
import Foundation
import UIKit

/// Routesetter actions; each one reloads the catalog afterwards.
extension GymCatalog {
    var activeGrades: [Grade] { grades.filter(\.isActive) }

    func photo(of sector: Sector) -> SectorPhoto? {
        sector.currentPhotoId.flatMap { photos[$0] }
    }

    /// Uploads a new sector photo. Problems in `removing` are taken down in
    /// this reset; the rest keep their pins on the new photo.
    func publishPhoto(_ image: UIImage, for sector: Sector, removing: Set<UUID>, note: String) async throws {
        guard let encoded = SectorPhotoEncoder.encode(image) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let path = try await backend.uploadSectorPhoto(gymId: gym.id, sectorId: sector.id, jpeg: encoded.jpeg)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try await backend.resetSector(
            sectorId: sector.id,
            expectedPhotoId: sector.currentPhotoId,
            storagePath: path,
            width: encoded.width,
            height: encoded.height,
            removeProblemIds: Array(removing),
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
        try await load()
    }

    func addProblem(to sector: Sector, at point: CGPoint, draft: ProblemDraft) async throws {
        guard let photoId = sector.currentPhotoId else { return }
        try await backend.addProblem(
            problemId: UUID(),
            sectorId: sector.id,
            expectedPhotoId: photoId,
            pinX: Double(point.x),
            pinY: Double(point.y),
            draft: draft
        )
        try await load()
    }

    func updateProblem(_ problem: ActiveProblem, with draft: ProblemDraft) async throws {
        try await backend.updateProblem(problemId: problem.id, draft: draft)
        try await load()
    }

    func moveProblem(_ problem: ActiveProblem, to point: CGPoint) async throws {
        try await backend.moveProblemPin(problemId: problem.id, pinX: Double(point.x), pinY: Double(point.y))
        try await load()
    }

    func takeDown(_ problem: ActiveProblem) async throws {
        try await backend.setProblemRemoved(problemId: problem.id, removed: true)
        try await load()
    }
}
