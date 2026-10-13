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
        // Suggest the new photo's holds right away. A failed detection only
        // means staff add holds by hand, so the photo stays published.
        if let photoId = sectors.first(where: { $0.id == sector.id })?.currentPhotoId {
            try? await detectHolds(on: photoId, image: image)
        }
    }

    /// Adds a problem; with a route, its start holds place the pin.
    @discardableResult
    func addProblem(to sector: Sector, at point: CGPoint, draft: ProblemDraft,
                    route: [RouteStep]? = nil) async throws -> UUID? {
        guard let photoId = sector.currentPhotoId else { return nil }
        let id = try await backend.addProblem(
            problemId: UUID(),
            sectorId: sector.id,
            expectedPhotoId: photoId,
            pinX: Double(point.x),
            pinY: Double(point.y),
            draft: draft,
            route: route
        )
        try await load()
        return id
    }

    func setRoute(of problem: ActiveProblem, to route: [RouteStep]) async throws {
        try await backend.setProblemRoute(problemId: problem.id, expectedPhotoId: problem.photoId, route: route)
        try await load()
    }

    // MARK: Holds

    func holds(on photo: SectorPhoto) async throws -> [PhotoHold] {
        try await backend.photoHolds(photoId: photo.id)
    }

    /// Runs the detector on a photo and stores what it found as suggestions.
    func detectHolds(on photoId: UUID, image: UIImage) async throws {
        guard let bitmap = PhotoPixels.bitmap(of: image, width: HoldDetector.workWidth) else { return }
        let found = await Task.detached(priority: .userInitiated) {
            HoldDetector.detect(rgba: bitmap.rgba, width: bitmap.width, height: bitmap.height)
        }.value
        try await backend.replaceAutoHolds(photoId: photoId, holds: found)
    }

    /// Detection for a photo that is already published.
    func detectHolds(on photo: SectorPhoto) async throws {
        guard let url = backend.photoURL(for: photo) else { return }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        try await detectHolds(on: photo.id, image: image)
    }

    /// A hold added by hand where the detector missed one.
    func addHold(on photo: SectorPhoto, x: Double, y: Double, color: HoldColor?) async throws -> PhotoHold {
        let hold = PhotoHold(photoId: photo.id, sectorId: photo.sectorId, x: x, y: y,
                             r: PhotoHold.defaultRadius, color: color)
        try await backend.upsertPhotoHold(hold)
        return hold
    }

    func deleteHold(_ hold: PhotoHold) async throws {
        try await backend.deletePhotoHold(id: hold.id)
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
