import UIKit

/// Prepares a wall photo for upload: upright, at most 2560 px on the long
/// edge, JPEG. Redrawing the bitmap drops all metadata (EXIF, GPS).
enum SectorPhotoEncoder {
    struct Encoded: Sendable {
        let jpeg: Data
        let width: Int
        let height: Int
    }

    static let maxLongEdge: CGFloat = 2560

    static func encode(_ image: UIImage) -> Encoded? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxLongEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.8) else { return nil }
        return Encoded(jpeg: jpeg, width: Int(target.width), height: Int(target.height))
    }
}
