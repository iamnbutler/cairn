import CoreGraphics
import CairnFrame
import Foundation
import CoreText
import Metal

/// Where a rasterised glyph lives: its atlas page and texel rect, and where the bitmap sits
/// relative to the glyph's pixel-snapped origin (x right, y down, in device pixels).
struct AtlasGlyph {
    var page: Int32 = -1     // -1: nothing to draw (blank glyph, e.g. a space)
    var isColor = false
    var x: UInt16 = 0, y: UInt16 = 0, w: UInt16 = 0, h: UInt16 = 0
    var left: Int32 = 0      // bitmap left edge minus origin x
    var top: Int32 = 0       // origin y minus bitmap top edge (positive: above the baseline)
}

/// macOS's "font smoothing": Core Graphics thickens glyph strokes by one of five amounts chosen
/// by the text colour's luminance, as AppKit and SwiftUI draw text (research/macos/
/// text-rendering.md §2; GPUI's `font_smoothing_dilation`). Off when the `AppleFontSmoothing`
/// default is the integer 0; an unset key means on.
public enum FontSmoothing {
    /// Whether text is thickened at all, read once.
    public static let enabled: Bool = {
        guard let v = UserDefaults.standard.object(forKey: "AppleFontSmoothing") as? NSNumber,
              CFGetTypeID(v) == CFNumberGetTypeID() else { return true }
        return v.intValue != 0
    }()

    /// The atlas key's smoothing for text in `color`: 0 for none, else 1 + the dilation level
    /// (0–4), `⌊4·luminance + ½⌋` with Rec. 709 luminance of the sRGB components. Measured
    /// against Core Graphics drawing coloured text on black with smoothing on: red, blue, orange,
    /// white and greys land exactly on these levels.
    public static func key(_ c: Color) -> UInt8 {
        guard enabled else { return 0 }
        let l = 0.2126 * Double(c.r) / 255 + 0.7152 * Double(c.g) / 255 + 0.0722 * Double(c.b) / 255
        return 1 + UInt8(max(0, min(4, Int((4 * l + 0.5).rounded(.down)))))
    }
}

/// Glyph bitmaps rasterised by Core Text at the backing scale, packed into pages.
///
/// Two kinds of page: `.r8Unorm` coverage masks (grayscale antialiasing, tinted by the text
/// colour) and `.bgra8Unorm` premultiplied colour bitmaps for colour glyphs (emoji). Glyphs are
/// keyed by (font, glyph, subpixel bin, scale, smoothing). Pages are append-only shelves, so a frame in
/// flight never sees a texel it reads change; `reset` drops everything and must only run when
/// the GPU is idle.
final class GlyphAtlas {
    static let pageSize = 2048
    /// Horizontal subpixel positions per pixel. Glyphs are cached per bin; y is pixel-snapped.
    static let subpixelBins = 8
    /// Beyond this many pages the renderer waits for the GPU and calls `reset`.
    static let maxPages = 8

    struct Key: Hashable { let font: FontKey; let glyph: CGGlyph; let bin: UInt8; let scale: Float; let smoothing: UInt8 }

    private let device: MTLDevice
    private(set) var maskPages: [MTLTexture] = []
    private(set) var colorPages: [MTLTexture] = []
    private var maskShelf = Shelf(), colorShelf = Shelf()
    private var glyphs: [Key: AtlasGlyph] = [:]
    private var scaledFonts: [ScaledKey: CTFont] = [:]
    private struct ScaledKey: Hashable { let font: FontKey; let scale: Float }

    var pageCount: Int { maskPages.count + colorPages.count }
    var glyphCount: Int { glyphs.count }

    init(device: MTLDevice) { self.device = device }

    func reset() {
        maskPages.removeAll(); colorPages.removeAll()
        maskShelf = Shelf(); colorShelf = Shelf()
        glyphs.removeAll(); scaledFonts.removeAll()
    }

    /// `smoothing` is `FontSmoothing.key` of the text's colour (ignored for colour glyphs).
    func glyph(_ font: FontKey, _ glyph: CGGlyph, bin: Int, scale: Float, isColor: Bool,
               smoothing: UInt8 = 0) -> AtlasGlyph {
        let sm = isColor ? 0 : smoothing
        let key = Key(font: font, glyph: glyph, bin: UInt8(bin), scale: scale, smoothing: sm)
        if let g = glyphs[key] { return g }
        let g = rasterise(font, glyph, bin: bin, scale: scale, isColor: isColor, smoothing: sm)
        glyphs[key] = g
        return g
    }

    private func scaled(_ font: FontKey, _ scale: Float) -> CTFont {
        let k = ScaledKey(font: font, scale: scale)
        if let f = scaledFonts[k] { return f }
        // The same point size under a scale transform, not a larger size: a larger size would
        // pick another optical size (SF Pro Display's glyphs at 28 pt instead of Text's at 14),
        // which is not what AppKit and SwiftUI draw on a 2x screen.
        var m = CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))
        let f = CTFontCreateCopyWithAttributes(font.font, CTFontGetSize(font.font), &m, nil)
        scaledFonts[k] = f
        return f
    }

    private func rasterise(_ font: FontKey, _ glyph: CGGlyph, bin: Int, scale: Float, isColor: Bool,
                           smoothing: UInt8) -> AtlasGlyph {
        let f = scaled(font, scale)
        var g = glyph
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(f, .default, &g, &bounds, 1)
        if bounds.isNull || bounds.isEmpty { return AtlasGlyph() }
        let dx = CGFloat(bin) / CGFloat(Self.subpixelBins)
        // Pixel bounds of the ink, padded by one pixel for antialiasing and one more for
        // smoothing's thickening. y up here.
        let pad = smoothing > 0 ? 2 : 1
        let x0 = Int((bounds.minX + dx).rounded(.down)) - pad
        let x1 = Int((bounds.maxX + dx).rounded(.up)) + pad
        let y0 = Int(bounds.minY.rounded(.down)) - pad
        let y1 = Int(bounds.maxY.rounded(.up)) + pad
        let w = x1 - x0, h = y1 - y0
        guard w > 0, h > 0, w <= Self.pageSize, h <= Self.pageSize else { return AtlasGlyph() }

        let bpp = isColor ? 4 : 1
        var pixels = [UInt8](repeating: 0, count: w * h * bpp)
        let drew: Bool = pixels.withUnsafeMutableBytes { buf in
            let ctx: CGContext?
            if isColor {
                ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)
            } else if smoothing > 0 {
                // Coverage only; the fill's grey picks how much Core Graphics thickens.
                ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            } else {
                ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)
            }
            guard let ctx else { return false }
            ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
            ctx.setAllowsFontSmoothing(smoothing > 0); ctx.setShouldSmoothFonts(smoothing > 0)
            ctx.setAllowsFontSubpixelPositioning(true); ctx.setShouldSubpixelPositionFonts(true)
            ctx.setAllowsFontSubpixelQuantization(false); ctx.setShouldSubpixelQuantizeFonts(false)
            if smoothing > 0 { ctx.setFillColor(gray: CGFloat(smoothing - 1) * 0.25, alpha: 1) }
            else if !isColor { ctx.setFillColor(gray: 1, alpha: 1) }
            var p = CGPoint(x: dx - CGFloat(x0), y: -CGFloat(y0))
            CTFontDrawGlyphs(f, &g, &p, 1, ctx)
            return true
        }
        guard drew else { return AtlasGlyph() }

        guard let (page, x, y) = place(w: w, h: h, isColor: isColor) else { return AtlasGlyph() }
        let tex = isColor ? colorPages[page] : maskPages[page]
        // A bitmap context's first row in memory is its top row, as Metal expects.
        pixels.withUnsafeBytes { buf in
            tex.replace(region: MTLRegionMake2D(x, y, w, h), mipmapLevel: 0,
                        withBytes: buf.baseAddress!, bytesPerRow: w * bpp)
        }
        return AtlasGlyph(page: Int32(page), isColor: isColor,
                          x: UInt16(x), y: UInt16(y), w: UInt16(w), h: UInt16(h),
                          left: Int32(x0), top: Int32(y1))
    }

    private func place(w: Int, h: Int, isColor: Bool) -> (Int, Int, Int)? {
        func go(_ pages: inout [MTLTexture], _ shelf: inout Shelf, _ format: MTLPixelFormat) -> (Int, Int, Int)? {
            if !pages.isEmpty, let (x, y) = shelf.alloc(w, h, Self.pageSize) { return (pages.count - 1, x, y) }
            pages.append(makePage(format))
            shelf = Shelf()
            guard let (x, y) = shelf.alloc(w, h, Self.pageSize) else { return nil }
            return (pages.count - 1, x, y)
        }
        return isColor ? go(&colorPages, &colorShelf, .bgra8Unorm) : go(&maskPages, &maskShelf, .r8Unorm)
    }

    private func makePage(_ format: MTLPixelFormat) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: Self.pageSize, height: Self.pageSize, mipmapped: false)
        d.usage = .shaderRead
        d.storageMode = .shared
        return device.makeTexture(descriptor: d)!
    }
}

/// Shelf packing: glyphs fill a row left to right; a new row starts below the tallest so far.
struct Shelf {
    var x = 0, y = 0, rowHeight = 0
    static let gap = 1

    mutating func alloc(_ w: Int, _ h: Int, _ size: Int) -> (Int, Int)? {
        if x + w > size { x = 0; y += rowHeight + Self.gap; rowHeight = 0 }
        if y + h > size || w > size { return nil }
        let at = (x, y)
        x += w + Self.gap
        rowHeight = max(rowHeight, h)
        return at
    }
}
