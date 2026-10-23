import CairnFrame
import CoreText
import Foundation

/// One run of glyphs in a single (possibly fallback) font, positioned relative to the line's
/// baseline origin in logical points, y up as Core Text reports it.
struct GlyphRun: @unchecked Sendable {
    let font: FontKey
    let isColor: Bool
    let glyphs: [CGGlyph]
    let positions: [CGPoint]
    let advances: [CGSize]
}

/// A shaped single line: what the renderer draws and what Lean lays out with, from one CTLine.
public struct ShapedLine: @unchecked Sendable {
    let runs: [GlyphRun]
    /// Caret offset before each Unicode scalar, plus one for the end: `scalars + 1` entries,
    /// starting at 0, nondecreasing, whole logical points (see `TextSystem.round`).
    public let offsets: [Int32]
    /// The line's width: the last offset.
    public var width: Int32 { offsets.last ?? 0 }
    /// Whole points above and below the baseline (per font, not per string).
    public let ascent: Int32
    public let descent: Int32
}

/// Core Text shaping with a cache. Thread-safe: the Lean thread asks for metrics while the render
/// thread draws, and both get the same `ShapedLine` for the same (font, string).
public final class TextSystem: @unchecked Sendable {
    public static let shared = TextSystem()

    private let lock = NSLock()
    private var fonts: [Font: CTFont] = [:]
    private var lines: [LineKey: ShapedLine] = [:]
    /// The cache is cleared (not evicted piecemeal) when it reaches this many lines.
    static let lineCapacity = 8192

    private struct LineKey: Hashable { let font: Font; let string: String }

    func ctFont(_ f: Font) -> CTFont {
        lock.lock(); defer { lock.unlock() }
        return ctFontLocked(f)
    }

    private func ctFontLocked(_ f: Font) -> CTFont {
        if let ct = fonts[f] { return ct }
        let ct = Fonts.make(f)
        fonts[f] = ct
        return ct
    }

    public func shape(_ font: Font, _ string: String) -> ShapedLine {
        let key = LineKey(font: font, string: string)
        lock.lock(); defer { lock.unlock() }
        if let line = lines[key] { return line }
        let line = Self.shape(ctFontLocked(font), string)
        if lines.count >= Self.lineCapacity { lines.removeAll(keepingCapacity: true) }
        lines[key] = line
        return line
    }

    /// Ascent and descent of a font, without shaping anything.
    public func vertical(_ font: Font) -> (ascent: Int32, descent: Int32) {
        let ct = ctFont(font)
        return (Self.round(CTFontGetAscent(ct)), Self.round(CTFontGetDescent(ct)))
    }

    /// The rounding rule for every length Lean sees: up to a whole point, except that values
    /// within 1/256 pt above a whole point snap down to it (so 20.000001 is 20, not 21).
    /// Monotone: x ≤ y implies round(x) ≤ round(y). round(0) = 0. Never below x - 1/256.
    static func round(_ x: CGFloat) -> Int32 {
        guard x.isFinite else { return 0 }
        let r = (x - 1.0 / 256).rounded(.up)
        return Int32(clamping: Int64(max(r, 0)))
    }

    static func shape(_ ct: CTFont, _ string: String) -> ShapedLine {
        let attr = NSAttributedString(string: string, attributes: [.font: ct])
        let line = CTLineCreateWithAttributedString(attr)
        let ctRuns = CTLineGetGlyphRuns(line) as! [CTRun]

        var runs: [GlyphRun] = []
        for r in ctRuns {
            let n = CTRunGetGlyphCount(r)
            guard n > 0 else { continue }
            let attrs = CTRunGetAttributes(r) as NSDictionary
            let runFont = attrs[kCTFontAttributeName] as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            var adv = [CGSize](repeating: .zero, count: n)
            let all = CFRange(location: 0, length: 0)
            CTRunGetGlyphs(r, all, &glyphs)
            CTRunGetPositions(r, all, &pos)
            CTRunGetAdvances(r, all, &adv)
            let color = CTFontGetSymbolicTraits(runFont).contains(.traitColorGlyphs)
            runs.append(GlyphRun(font: FontKey(font: runFont), isColor: color,
                                 glyphs: glyphs, positions: pos, advances: adv))
        }

        // Every caret offset comes from this one line (never from measuring prefixes, which
        // kerning makes disagree). Scalar boundaries become UTF-16 indices by summing each
        // scalar's UTF-16 length, so no query lands inside a surrogate pair (Core Text answers
        // 0 there). Boundaries inside a grapheme cluster report the cluster's end; we keep that.
        // Text is left-to-right in M1: a running max makes RTL or bidi lines nondecreasing
        // (and wrong as carets), so `TextMetrics.Valid` holds whatever Core Text returns.
        var offsets: [Int32] = [0]
        offsets.reserveCapacity(string.unicodeScalars.count + 1)
        var u = 0
        var running: Int32 = 0
        for s in string.unicodeScalars {
            u += s.utf16.count
            running = max(running, round(CTLineGetOffsetForStringIndex(line, u, nil)))
            offsets.append(running)
        }
        // The box must cover the whole advance even if a caret offset undershoots it.
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        offsets[offsets.count - 1] = max(running, round(width))
        return ShapedLine(runs: runs, offsets: offsets,
                          ascent: round(CTFontGetAscent(ct)), descent: round(CTFontGetDescent(ct)))
    }
}
