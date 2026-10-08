import BoulderKit
import Foundation

/// JSON files in Application Support: the outbox of pending writes and the
/// last downloaded catalog of each gym (per user — it holds my ascents).
enum LocalStore {
    private static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Wspinaczka", directoryHint: .isDirectory)
    }()

    static let outboxURL = root.appending(path: "outbox.json")

    private static let catalogsURL = root.appending(path: "catalogs", directoryHint: .isDirectory)

    static func catalogURL(userId: UUID, gymId: UUID) -> URL {
        catalogsURL
            .appending(path: userId.uuidString, directoryHint: .isDirectory)
            .appending(path: "\(gymId.uuidString).json")
    }

    static func read<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write(_ value: some Encodable, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Catalog cache

    static func catalog(userId: UUID, gymId: UUID) -> CatalogSnapshot? {
        guard let snapshot = read(CatalogSnapshot.self, from: catalogURL(userId: userId, gymId: gymId)),
              snapshot.isCurrent, snapshot.gymId == gymId else { return nil }
        return snapshot
    }

    static func saveCatalog(_ snapshot: CatalogSnapshot, userId: UUID) {
        // A cache: failing to write it only costs a slower next start.
        try? write(snapshot, to: catalogURL(userId: userId, gymId: snapshot.gymId))
    }

    /// Signing out leaves no private data of the account behind.
    static func removeCatalogs() {
        try? FileManager.default.removeItem(at: catalogsURL)
    }
}
