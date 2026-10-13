import UIKit

/// A photo as raw pixels, for the hold detector.
enum PhotoPixels {
    struct Bitmap: Sendable {
        let rgba: [UInt8]
        let width: Int
        let height: Int
    }

    /// The image upright, scaled to `width` pixels wide, as 8-bit RGBA.
    static func bitmap(of image: UIImage, width: Int) -> Bitmap? {
        let size = image.size
        guard size.width > 0, size.height > 0, width > 0 else { return nil }
        let height = max(1, Int((Double(width) * size.height / size.width).rounded()))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scaled = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            image.draw(in: rect)
        }
        guard let cgImage = scaled.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: rect)
            return true
        }
        return drawn ? Bitmap(rgba: bytes, width: width, height: height) : nil
    }
}
