import Foundation

/// The last catalog of a gym downloaded from the server, kept on the device so
/// the gym opens instantly (and offline) before it is refreshed.
public struct CatalogSnapshot: Hashable, Codable, Sendable {
    /// Bump when the stored shape changes; older files are ignored.
    public static let currentVersion = 1

    public let version: Int
    public let gymId: UUID
    public let savedAt: Date
    public let grades: [Grade]
    public let sectors: [Sector]
    public let photos: [SectorPhoto]
    public let problems: [ActiveProblem]
    /// As confirmed by the server; pending writes are merged on top when shown.
    public let myAscents: [Ascent]

    public init(gymId: UUID, savedAt: Date = .now, grades: [Grade], sectors: [Sector],
                photos: [SectorPhoto], problems: [ActiveProblem], myAscents: [Ascent]) {
        self.version = Self.currentVersion
        self.gymId = gymId
        self.savedAt = savedAt
        self.grades = grades
        self.sectors = sectors
        self.photos = photos
        self.problems = problems
        self.myAscents = myAscents
    }

    public var isCurrent: Bool { version == Self.currentVersion }
}
