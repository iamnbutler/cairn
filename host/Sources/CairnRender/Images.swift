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
/// Thread-safe. Entries stay until replaced or removed (a reload that fails removes its source),
/// unless a budget is set (`Sub.imageCache`, ^1011): then past `budget` bytes of pixels the store
/// drops the entries used least recently, never one the latest frame draws (`setDrawn`) nor the
/// one just put, and tells `onDrop` of each after it is gone. `onDrop` hears of every removal,
/// a failed reload's too, so an app never takes a dropped image for ready.
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
    /// The byte budget, while an `imageCache` subscription runs.
    private var budget: Int?
    /// Told each source dropped, after it is gone (outside the lock).
    private var onDrop: (@Sendable (String) -> Void)?
    /// The sources the latest applied frame draws: never dropped.
    private var drawn: Set<String> = []
    /// When each entry was last put or drawn; the smallest is dropped first.
    private var used: [String: Int] = [:]
    private var clock = 0
    /// The pixel bytes of every entry.
    private var held = 0
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
        lock.lock()
        let e = Entry(width: decoded.width, height: decoded.height, pixels: decoded.pixels, generation: generation)
        if let old = entries[source] { held -= old.pixels.bytes.count }
        entries[source] = e
        held += e.pixels.bytes.count
        clock += 1
        used[source] = clock
        let dropped = trim(keeping: source)
        let tell = onDrop
        lock.unlock()
        for s in dropped { tell?(s) }
        return e
    }

    /// Removes `source`'s entry, and tells `onDrop` if there was one.
    public func remove(_ source: String) {
        lock.lock()
        let had = drop(source)
        let tell = onDrop
        lock.unlock()
        if had { tell?(source) }
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    /// The pixel bytes the store holds.
    public var bytes: Int {
        lock.lock(); defer { lock.unlock() }
        return held
    }

    /// Keep within `bytes` (nil: keep everything), telling `onDrop` of each source dropped, from
    /// now on. Trims at once.
    public func setBudget(_ bytes: Int?, onDrop: (@Sendable (String) -> Void)?) {
        lock.lock()
        budget = bytes.map { max(0, $0) }
        self.onDrop = onDrop
        let dropped = trim(keeping: nil)
        lock.unlock()
        for s in dropped { onDrop?(s) }
    }

    /// The sources the frame just applied draws: kept whatever the budget, and counted as used
    /// now. The ones it no longer draws may be dropped at once.
    public func setDrawn(_ sources: Set<String>) {
        lock.lock()
        drawn = sources
        clock += 1
        for s in sources where entries[s] != nil { used[s] = clock }
        let dropped = trim(keeping: nil)
        let tell = onDrop
        lock.unlock()
        for s in dropped { tell?(s) }
    }

    /// Under `lock`: drop `source`'s entry; whether there was one.
    private func drop(_ source: String) -> Bool {
        guard let e = entries.removeValue(forKey: source) else { return false }
        held -= e.pixels.bytes.count
        used[source] = nil
        return true
    }

    /// Under `lock`: while over budget, drop the entry used least recently that is neither drawn
    /// nor `keeping`. The sources dropped, in order.
    private func trim(keeping: String?) -> [String] {
        guard let budget, held > budget else { return [] }
        let order = used.filter { $0.key != keeping && !drawn.contains($0.key) }
            .sorted { $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key) }
        var out: [String] = []
        for (s, _) in order {
            guard held > budget else { break }
            if drop(s) { out.append(s) }
        }
        return out
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
