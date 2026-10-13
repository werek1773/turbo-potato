import BoulderKit
import ImageIO
import SwiftUI
import Synchronization
import UIKit

/// Sector photos, kept in memory and on disk. A storage path is never
/// overwritten (a reset uploads a new file), so a cached photo never goes
/// stale and is keyed by its path alone.
final class PhotoCache: @unchecked Sendable {
    // @unchecked: NSCache is thread-safe, the in-flight table is behind a
    // Mutex and everything else is immutable.
    static let shared = PhotoCache()

    /// Long edge of the decoded bitmap: sharp on a phone, a third of the
    /// memory of the uploaded 2560 px.
    private static let maxPixelSize = 2000

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let session: URLSession
    private let inFlight = Mutex<[String: Task<UIImage, any Error>]>([:])

    private init() {
        memory.totalCostLimit = 150 * 1024 * 1024
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "SectorPhotos", directoryHint: .isDirectory)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil // The files below are the cache.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    /// Already decoded in memory: shown without a placeholder frame.
    func memoryImage(for photo: SectorPhoto) -> UIImage? {
        memory.object(forKey: photo.storagePath as NSString)
    }

    func image(for photo: SectorPhoto, from url: URL) async throws -> UIImage {
        let key = photo.storagePath
        if let image = memory.object(forKey: key as NSString) { return image }
        let task = inFlight.withLock { tasks in
            if let task = tasks[key] { return task }
            let task = Task.detached(priority: .userInitiated) { [self] in
                defer { _ = inFlight.withLock { $0.removeValue(forKey: key) } }
                return try await load(key: key, from: url)
            }
            tasks[key] = task
            return task
        }
        return try await task.value
    }

    private func load(key: String, from url: URL) async throws -> UIImage {
        let file = directory.appending(path: key.replacingOccurrences(of: "/", with: "_"))
        if let data = try? Data(contentsOf: file), let image = Self.decode(data) {
            remember(image, for: key)
            return image
        }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let image = Self.decode(data) else {
            throw URLError(.badServerResponse)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        remember(image, for: key)
        return image
    }

    private func remember(_ image: UIImage, for key: String) {
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        memory.setObject(image, forKey: key as NSString, cost: Int(pixels) * 4)
    }

    /// Decodes off the main thread, downsampled, ready to draw.
    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// A sector photo from the cache, with a placeholder while it loads and a
/// tap to retry when it could not be downloaded. Size it with `aspectRatio`.
struct CachedPhotoView: View {
    let photo: SectorPhoto

    private enum Phase {
        case loading
        case loaded(UIImage)
        case failed
    }

    @State private var phase: Phase
    @State private var attempt = 0

    init(photo: SectorPhoto) {
        self.photo = photo
        _phase = State(initialValue: PhotoCache.shared.memoryImage(for: photo).map(Phase.loaded) ?? .loading)
    }

    var body: some View {
        content
            .task(id: TaskKey(path: photo.storagePath, attempt: attempt)) { await load() }
            .onChange(of: Connectivity.shared.isOnline) { _, online in
                if online, case .failed = phase { attempt += 1 }
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case let .loaded(image):
            Image(uiImage: image).resizable()
        case .loading:
            Rectangle().fill(.quaternary)
                .overlay { ProgressView() }
        case .failed:
            Rectangle().fill(.quaternary)
                .overlay {
                    Button {
                        attempt += 1
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise").font(.title3)
                            Text("Nie udało się wczytać zdjęcia.\nDotknij, aby spróbować ponownie.")
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.secondary)
                        .padding()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
        }
    }

    private struct TaskKey: Hashable {
        let path: String
        let attempt: Int
    }

    private func load() async {
        if let cached = PhotoCache.shared.memoryImage(for: photo) {
            phase = .loaded(cached)
            return
        }
        guard let url = Backend.shared.photoURL(for: photo) else {
            phase = .failed
            return
        }
        phase = .loading
        do {
            phase = .loaded(try await PhotoCache.shared.image(for: photo, from: url))
        } catch {
            if Task.isCancelled { return }
            phase = .failed
        }
    }
}
