import AppKit
import CairnFrame
import CairnRender
import CoreText
import Foundation

/// `cairn_text_metrics` (Core Text, through the host's C ABI) against what Lean's layout assumes,
/// `TextMetrics.Valid`, and against Lean's own view of it (`TextMetrics.host`, whose `normalise`
/// must be the identity on a well-behaved host). Fonts across families, sizes (0, 1, huge),
/// weights, italic, widths, tracking and tabular digits; strings with clusters, RTL, controls and invalid UTF-8.
final class MetricsSuite: Suite {
    let name = "metrics"
    let crashCheck = "text.metrics"
    let checks: [String: CheckInfo] = [
        "text.metrics": CheckInfo(
            title: "cairn_text_metrics returns n + 3 values: ascent, descent ≥ 0, offsets from 0, nondecreasing; Lean sees the same numbers",
            trusted: ["host/Sources/CairnRender/Metrics.swift", "host/Sources/CairnRender/TextSystem.swift",
                      "host/Sources/CairnRender/Fonts.swift", "Core Text"],
            oracle: "TextMetrics.Valid (shape), Lean's TextMetrics.host through cairn_text_host_check (values)"),
        "text.metrics.carets": CheckInfo(
            title: "On left-to-right text the offsets are Core Text's own caret offsets (the running max never changes one)",
            trusted: ["host/Sources/CairnRender/TextSystem.swift", "Core Text"],
            oracle: "CTLineGetOffsetForStringIndex on a fresh CTLine, rounded the same way"),
    ]

    func cases(for n: Int) -> Int { n }
    func setUp() { Lean.start() }

    struct Case {
        var family: UInt32, size: UInt32, weight: UInt32, italic: Bool
        var width: FontWidth = .standard, tracking: Int32 = 0, tabular = false
        var text: String
        /// Raw bytes to send instead of `text`'s UTF-8 (invalid UTF-8), when set.
        var bytes: [UInt8]?
        var font: Font {
            Font(family: family, size: size, weight: weight, italic: italic, width: width,
                 tracking: tracking, tabular: tabular)
        }
        var description: String {
            "family \(family) size \(size) weight \(weight) italic \(italic) width \(width) "
                + "tracking \(tracking) tabular \(tabular) "
                + (bytes.map { "bytes hex:" + hex($0) } ?? Dump.str(text))
        }
    }

    func gen(_ g: inout SplitMix) -> Case {
        let family: UInt32 = g.weighted([(6, { $0.elem([0, 1]) }), (1, { _ in 2 }), (1, { UInt32(truncatingIfNeeded: $0.next()) })])
        let size: UInt32 = g.weighted([
            (6, { UInt32($0.range(8, 48)) }),
            (2, { $0.elem([0, 1, 2, 3, 1023, 1024, 1025, 4096, UInt32.max]) }),
            (1, { UInt32($0.range(49, 400)) }),
        ])
        let weight: UInt32 = g.weighted([(4, { UInt32($0.below(10) * 100) }), (2, { UInt32($0.range(0, 1000)) }),
                                          (1, { $0.elem([0, 49, 50, 949, 950, UInt32.max]) })])
        let italic = g.chance(1, 4)
        let width: FontWidth = g.weighted([(4, { _ in .standard }), (1, { $0.elem([.condensed, .expanded, .compressed]) })])
        let tracking: Int32 = g.weighted([(4, { _ in 0 }), (2, { Int32($0.range(-300, 600)) }),
                                          (1, { $0.elem([-100_000, 100_000, Int32.min, Int32.max]) })])
        let tabular = g.chance(1, 4)
        let text = g.chance(1, 10) ? TextPool.string(&g, maxParts: 80) : TextPool.string(&g)
        var bytes: [UInt8]?
        if g.chance(1, 12) {
            // Invalid UTF-8: a stray continuation, a truncated sequence, an overlong or a surrogate.
            var b = Array(text.utf8)
            let bad: [UInt8] = g.elem([[0x80], [0xC3], [0xE2, 0x82], [0xF0, 0x9F, 0x98], [0xC0, 0xAF],
                                       [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xFF], [0xFE]])
            b.insert(contentsOf: bad, at: g.range(0, b.count))
            bytes = b
        }
        return Case(family: family, size: size, weight: weight, italic: italic, width: width,
                    tracking: tracking, tabular: tabular, text: text, bytes: bytes)
    }

    static func metrics(_ c: Case, cap: Int? = nil) -> (count: Int32, values: [Int32]) {
        let bytes = c.bytes ?? Array(c.text.utf8)
        var out = [Int32](repeating: Int32.min, count: max(cap ?? bytes.count + 8, 1))
        let n = bytes.withUnsafeBufferPointer { b in
            out.withUnsafeMutableBufferPointer { o in
                cairn_text_metrics(c.family, c.size, c.weight, c.font.style, c.tracking, b.baseAddress, b.count,
                                   o.baseAddress, cap ?? o.count)
            }
        }
        return (n, out)
    }

    /// A strong right-to-left or bidi-control scalar (approximate: the RTL blocks and controls).
    static func bidi(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF,
             0x200F, 0x202A...0x202E, 0x2066...0x2069, 0x061C:
            return true
        default: return false
        }
    }

    /// The same font the host makes (Fonts.make, an internal of CairnRender), for the caret oracle.
    static func ctFont(_ f: Font) -> CTFont {
        let size = CGFloat(min(max(f.size, 1), 1024))
        let hundred = min(max((Int(f.weight) + 50) / 100, 1), 9)
        let w: NSFont.Weight = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black][hundred - 1]
        let widths: [FontWidth: NSFont.Width] = [.standard: .standard, .condensed: .condensed,
                                                 .expanded: .expanded, .compressed: .compressed]
        var ns = f.family == 1 ? NSFont.monospacedSystemFont(ofSize: size, weight: w)
                               : NSFont.systemFont(ofSize: size, weight: w, width: widths[f.width]!)
        if f.tabular {
            let d = ns.fontDescriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
            ns = NSFont(descriptor: d, size: size) ?? ns
        }
        let base = ns as CTFont
        guard f.italic else { return base }
        return CTFontCreateCopyWithSymbolicTraits(base, 0, nil, .traitItalic, .traitItalic) ?? base
    }

    /// The attributes a line in font `f` is shaped with: the font, and its tracking.
    static func attributes(_ f: Font) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.font: ctFont(f)]
        if f.tracking != 0 { a[NSAttributedString.Key(kCTTrackingAttributeName as String)] = CGFloat(f.tracking) / 100 }
        return a
    }

    static func round(_ x: CGFloat) -> Int32 {
        guard x.isFinite else { return 0 }
        return Int32(clamping: Int64(max((x - 1.0 / 256).rounded(.up), 0)))
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let c = gen(&g)
        let check = "text.metrics"
        let repro = { c.description }
        // What the host means by the string: invalid UTF-8 repaired with U+FFFD.
        let text = c.bytes.map { String(decoding: $0, as: UTF8.self) } ?? c.text
        let n = text.unicodeScalars.count
        let (count, all) = Self.metrics(c, cap: n + 3)
        if c.bytes != nil { r.count(check, "invalidUTF8") }
        guard r.expect(check, Int(count) == n + 3, "count \(count), want \(n + 3) for \(n) scalars", repro: repro) else { return }
        let ascent = all[0], descent = all[1], offs = Array(all[2...])
        r.expect(check, ascent >= 0 && descent >= 0, "ascent \(ascent) descent \(descent)", repro: repro)
        r.expect(check, offs.first == 0, "offset 0 is \(offs[0])", repro: repro)
        if let i = offs.indices.dropFirst().first(where: { offs[$0] < offs[$0 - 1] }) {
            r.fail(check, "offsets decrease at \(i): \(offs[i - 1]) then \(offs[i])", repro: repro)
        }
        let v = TextSystem.shared.vertical(c.font)
        r.expect(check, v == (ascent, descent), "vertical \(v) but metrics give \(ascent), \(descent)", repro: repro)

        // A short buffer gets a prefix, and the full count; no buffer gets just the count.
        let cap = g.range(0, n + 3)
        let (count2, part) = Self.metrics(c, cap: cap)
        r.expect(check, count2 == count && Array(part.prefix(cap)) == Array(all.prefix(cap))
                     && (cap == 0 || part.count == cap),
                 "cap \(cap): count \(count2), prefix differs", repro: repro)
        let bytes = c.bytes ?? Array(c.text.utf8)
        let count3 = bytes.withUnsafeBufferPointer { cairn_text_metrics(c.family, c.size, c.weight, c.font.style, c.tracking, $0.baseAddress, $0.count, nil, 0) }
        r.expect(check, count3 == count, "count with no buffer \(count3), want \(count)", repro: repro)

        // Lean's view: linked, and normalise is the identity (only valid UTF-8 crosses to Lean).
        if c.bytes == nil {
            let lean = Lean.hostMetrics(c.font, c.text)
            r.expect(check, lean.first == 1, "Lean says no host is linked", repro: repro)
            r.expect(check, Array(lean.dropFirst()) == Array(all.prefix(n + 3)),
                     "Lean sees \(Array(lean.dropFirst()).prefix(12)), host gave \(all.prefix(12))", repro: repro)
        }

        // Carets: on text with no right-to-left scalar, the caret after a grapheme is at or right
        // of where every glyph drawn for the text before it ends (its advance), less a slack of
        // 1 pt + 0.15 em for kerning, fallback fonts and rounding. Core Text's own caret offsets are counted against that.
        guard !text.unicodeScalars.contains(where: Self.bidi) else { r.count("text.metrics.carets", "skippedRTL"); return }
        let carets = "text.metrics.carets"
        let attr = NSAttributedString(string: text, attributes: Self.attributes(c.font))
        let line = CTLineCreateWithAttributedString(attr)
        var ends: [(index: Int, x: CGFloat)] = []  // where each glyph's advance ends, by string index
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let k = CTRunGetGlyphCount(run)
            var idx = [CFIndex](repeating: 0, count: k), pos = [CGPoint](repeating: .zero, count: k)
            var adv = [CGSize](repeating: .zero, count: k)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &idx)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &pos)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &adv)
            // A glyph ends where its advance does, or where the next glyph of its run starts if that is
            // sooner (contextual spacing, as for runs of CJK brackets, moves positions, not advances).
            for j in 0..<k {
                let next = j + 1 < k && pos[j + 1].x > pos[j].x ? pos[j + 1].x : .infinity
                ends.append((idx[j], min(pos[j].x + adv[j].width, next)))
            }
        }
        ends.sort { $0.index < $1.index }
        r.count(carets, "scalars", n)
        let sc = Array(text.unicodeScalars)
        var k = 0, u = 0, j = 0
        var painted: CGFloat = 0  // the furthest glyph end for text before u
        for ch in text {
            for s in ch.unicodeScalars { u += s.utf16.count }
            k += ch.unicodeScalars.count
            while j < ends.count, ends[j].index < u { painted = max(painted, ends[j].x); j += 1 }
            let floor = Self.round(painted) - 1 - Int32(Double(min(max(c.size, 1), 1024)) * 0.15)
            let ct = Self.round(CTLineGetOffsetForStringIndex(line, u, nil))
            if offs[k] < floor, ct != 0, offs[k] == ct {
                // Core Text's own caret sits inside a painted glyph (a LastResort glyph for an
                // unassigned scalar, compressed CJK brackets): the host passes it on. Counted, and
                // listed in docs/fuzz.md, but not the host's to fix.
                r.count(carets, "coreTextCaretInsideGlyph")
                r.ran(carets)
                continue
            }
            r.count(carets, ct >= floor ? "coreTextAtOrAfterGlyphs" : ct == 0 ? "coreTextZeroAfterGlyphs" : "coreTextBeforeGlyphs")
            r.expect(carets, offs[k] >= floor,
                     "offset \(k) (after U+\(String(sc[k - 1].value, radix: 16, uppercase: true))) is \(offs[k]), left of the glyphs before it, which end at \(Self.round(painted)) (Core Text's caret \(ct))",
                     repro: repro)
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "cairn_text_metrics on " + gen(&g).description
    }
}
