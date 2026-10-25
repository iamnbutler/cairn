import CairnFrame
import CoreGraphics
import Foundation
import ImageIO

/// Decoded images, by the source a `loadImage` request and an `image` draw name.
///
/// The `loadImage` handler decodes and puts; the renderer reads the pixels when it first draws a
/// source (or after the source was put again) and keeps its own texture. Lean never holds pixels:
/// it learns the pixel size from the reply and lays the node out at the size it chose.
///
/// Thread-safe. Entries stay until replaced or removed (a reload that fails removes its source);
/// nothing is evicted yet.
public final class ImageStore: @unchecked Sendable {
    public static let shared = ImageStore()

    /// One decoded image: `width`×`height` is the size the reply reports (the oriented original);
    /// `pixels` holds it at most `maxSide` pixels on its long side, premultiplied BGRA in sRGB.
    public struct Entry: Sendable {
        public let width: Int, height: Int
        public let pixels: Pixels
        /// Increases each time any source is put in any store, so a renderer can tell a replaced
        /// image (or another store's) apart.
        public let generation: Int
    }

    public struct Pixels: Sendable {
        public let width: Int, height: Int
        public let bytes: [UInt8]  // width * height * 4, rows top to bottom
    }

    /// The long side of the pixels kept for drawing; larger images are scaled down on decode.
    public static let maxSide = 4096

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private static let generations = NSLock()
    nonisolated(unsafe) private static var lastGeneration = 0

    public init() {}

    public func entry(_ source: String) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[source]
    }

    @discardableResult
    public func put(_ source: String, _ decoded: Decoded) -> Entry {
        Self.generations.lock()
        Self.lastGeneration += 1
        let generation = Self.lastGeneration
        Self.generations.unlock()
        lock.lock(); defer { lock.unlock() }
        let e = Entry(width: decoded.width, height: decoded.height, pixels: decoded.pixels, generation: generation)
        entries[source] = e
        return e
    }

    public func remove(_ source: String) {
        lock.lock(); defer { lock.unlock() }
        entries[source] = nil
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    /// An image decoded from bytes: its oriented pixel size and the pixels to draw.
    public struct Decoded: Sendable {
        public let width: Int, height: Int
        public let pixels: Pixels
    }

    /// Decodes the first image in `data` (any format ImageIO reads), applying its EXIF
    /// orientation. Nil when ImageIO finds no image.
    public static func decode(_ data: Data) -> Decoded? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let ph = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              pw > 0, ph > 0
        else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        // Orientations 5–8 turn the image a quarter: width and height swap.
        let (w, h) = (5...8).contains(orientation) ? (ph, pw) : (pw, ph)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(w, h), maxSide),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
              let pixels = bgra(img) else { return nil }
        return Decoded(width: w, height: h, pixels: pixels)
    }

    /// `img` drawn into premultiplied BGRA (little-endian ARGB words) in sRGB.
    static func bgra(_ img: CGImage) -> Pixels? {
        let w = img.width, h = img.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Pixels(width: w, height: h, bytes: bytes) : nil
    }
}
