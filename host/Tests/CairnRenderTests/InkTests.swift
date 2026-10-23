import CairnFrame
@testable import CairnRender
import Foundation
import Testing

/// Ink bounds of everything painted (alpha > `threshold`) in device pixels, half-open.
func inkBounds(_ img: Image, threshold: UInt8 = 0) -> PixelRect? {
    var b: PixelRect?
    for y in 0..<img.height {
        for x in 0..<img.width where img.bgra[(y * img.width + x) * 4 + 3] > threshold {
            if let c = b {
                b = PixelRect(x0: min(c.x0, x), y0: min(c.y0, y), x1: max(c.x1, x + 1), y1: max(c.y1, y + 1))
            } else {
                b = PixelRect(x0: x, y0: y, x1: x + 1, y1: y + 1)
            }
        }
    }
    return b
}

/// How far (logical points) the painted ink of one text draw extends past the box Lean computes
/// from the metrics: x from the origin to origin + last offset, y from baseline − ascent to
/// baseline + descent. Zero or negative means inside.
func overhang(_ f: Font, _ s: String, scale: Float) throws -> (left: Double, right: Double, top: Double, bottom: Double)? {
    let line = TextSystem.shared.shape(f, s)
    let pad: Int32 = 20
    let origin = P(pad, pad + line.ascent)
    let fr = frame(line.width + 2 * pad, line.ascent + line.descent + 2 * pad, [text(origin.x, origin.y, s, font: f)])
    let img = try withRenderer { r -> Image in
        let saved = r.clearColor
        r.clearColor = Color(r: 0, g: 0, b: 0, a: 0)
        defer { r.clearColor = saved }
        return try r.image(fr, scale: scale)
    }
    // Alpha above 8/255: ignore the faintest antialiasing fringe.
    guard let ink = inkBounds(img, threshold: 8) else { return nil }
    let sc = Double(scale)
    return (left: Double(origin.x) - Double(ink.x0) / sc,
            right: Double(ink.x1) / sc - Double(origin.x + line.width),
            top: Double(origin.y - line.ascent) - Double(ink.y0) / sc,
            bottom: Double(ink.y1) / sc - Double(origin.y + line.descent))
}

@Suite struct InkTests {
    static let rtl: Set<String> = ["abאבc", "عربي"]

    /// Upright left-to-right text (Latin, accents, CJK, Hangul, emoji, at 11–40 pt, both
    /// families): every painted pixel lies inside Lean's box, at 1x and 2x.
    @Test(arguments: [Float(1), 2]) func uprightInkInsideLeanBox(_ scale: Float) throws {
        for f in sampleFonts where !f.italic {
            for s in sampleStrings where !s.isEmpty && !Self.rtl.contains(s) {
                guard let o = try overhang(f, s, scale: scale) else { continue }
                #expect(o.left <= 0 && o.right <= 0 && o.top <= 0 && o.bottom <= 0,
                        "\(f) \(s.debugDescription) @\(scale)x overhangs \(o)")
            }
        }
    }

    /// Italic glyphs lean past their advance and RTL scripts sit lower; the overhang is at most
    /// 1 pt on any side (measured: 1 pt left/right for semibold italic 17, 1 pt below for Arabic).
    /// Layout that must contain such text pads by 1 pt.
    @Test(arguments: [Float(1), 2]) func italicAndRTLOverhangAtMostOnePoint(_ scale: Float) throws {
        for f in sampleFonts {
            for s in sampleStrings where !s.isEmpty && (f.italic || Self.rtl.contains(s)) {
                guard let o = try overhang(f, s, scale: scale) else { continue }
                #expect(max(o.left, o.right, o.top, o.bottom) <= 1,
                        "\(f) \(s.debugDescription) @\(scale)x overhangs \(o)")
            }
        }
    }
}
