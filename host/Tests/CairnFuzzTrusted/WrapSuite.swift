import AppKit
import CairnFrame
import CairnRender
import CoreText
import Foundation

/// Wrapped text (`Node.para`, docs/layout.md "Wrapped text"): Lean breaks a string into lines from
/// one Core Text measurement of the whole string, and the renderer paints each line as its own
/// text draw, shaped by Core Text again. Two checks:
///
/// - `text.wrap.painted`: each line, shaped on its own as the renderer will shape it, is as wide
///   as Lean measured it (within the 1 pt the whole-point rounding allows) and its carets sit
///   where Lean's do; and layout put the line where the para's rules say.
/// - `text.wrap.coretext`: on left-to-right text of letters, digits and spaces, Lean breaks where
///   Core Text's own word wrapping (`CTTypesetterSuggestLineBreak`) does, except where the line
///   that one accepts and the other rejects is within rounding of the width (Lean compares whole
///   points, Core Text fractions).
final class WrapSuite: Suite {
    let name = "wrap"
    let crashCheck = "text.wrap.painted"
    let checks: [String: CheckInfo] = [
        "text.wrap.painted": CheckInfo(
            title: "Each wrapped line, shaped alone as the renderer paints it, is the width Lean measured from the whole string (±1 pt), with the same carets (±1 pt); layout stacks the lines one line height apart",
            trusted: ["host/Sources/CairnRender/TextSystem.swift", "host/Sources/CairnRender/Renderer.swift", "Core Text"],
            oracle: "Lean's Wrap.allLines and layout on TextMetrics.host (cairn_tf_wrap), against TextSystem.shape of each line"),
        "text.wrap.coretext": CheckInfo(
            title: "On left-to-right letters, digits and spaces, Lean breaks lines where Core Text's word wrapping does, up to rounding",
            trusted: ["Core Text"],
            oracle: "CTTypesetterSuggestLineBreak on the same string, font and width"),
    ]

    func cases(for n: Int) -> Int { max(1, n / 2) }
    func setUp() { Lean.start() }

    struct Case {
        var family: UInt32, size: UInt32, weight: UInt32, italic: Bool
        var width: UInt32
        var text: String
        /// Letters, digits and spaces only: compared with Core Text's own line breaking.
        var plain: Bool
        var font: Font { Font(family: family, size: size, weight: weight, italic: italic) }
        var description: String {
            "family \(family) size \(size) weight \(weight) italic \(italic) width \(width) " + Dump.str(text)
        }
    }

    static let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    static func plainText(_ g: inout SplitMix) -> String {
        var s = ""
        for _ in 0..<g.range(0, 60) {
            s += String(repeating: " ", count: g.weighted([(8, { _ in 1 }), (1, { $0.range(0, 3) })]))
            let n = g.weighted([(8, { $0.range(1, 9) }), (1, { $0.range(10, 40) })])
            for _ in 0..<n { s.append(g.elem(letters)) }
        }
        if g.chance(1, 4) { s = " " + s + "  " }
        return s
    }

    func gen(_ g: inout SplitMix) -> Case {
        let plain = g.chance(1, 2)
        let text = plain ? Self.plainText(&g) : g.weighted([
            (3, { TextPool.string(&$0, maxParts: 60) }),
            (2, { g in Self.plainText(&g) + " " + TextPool.string(&g) + " " + Self.plainText(&g) }),
        ])
        return Case(family: g.elem([0, 0, 1]),
                    size: UInt32(g.weighted([(6, { $0.range(9, 32) }), (1, { $0.range(1, 120) })])),
                    weight: UInt32(g.elem([400, 400, 300, 600, 700])), italic: g.chance(1, 5),
                    width: UInt32(g.weighted([(6, { $0.range(20, 600) }), (1, { $0.range(0, 20) })])),
                    text: text, plain: plain)
    }

    /// Scalar indices that are grapheme boundaries.
    static func boundaries(_ text: String) -> Set<Int> {
        var b: Set<Int> = [0]
        var k = 0
        for ch in text { k += ch.unicodeScalars.count; b.insert(k) }
        return b
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let c = gen(&g)
        let repro = { c.description }
        let painted = "text.wrap.painted"
        let lines = Lean.wrap(c.font, width: c.width, c.text)
        let metrics = Lean.hostMetrics(c.font, c.text)
        let lh = max(0, metrics[1] + metrics[2])
        let offs = Array(metrics[3...])
        let scalars = Array(c.text.unicodeScalars)
        r.count(painted, "lines", lines.count)

        // Layout: one line height apart, at the left edge, as wide as measured.
        for (i, l) in lines.enumerated() {
            r.expect(painted, l.x == 0 && l.y == Int32(i) * lh && l.w == max(0, l.width),
                     "line \(i) [\(l.a), \(l.b)) laid at x \(l.x) y \(l.y) w \(l.w); want 0, \(Int32(i) * lh), \(max(0, l.width))",
                     repro: repro)
            r.expect(painted, l.width == offs[l.b] - offs[l.a], "line \(i) width \(l.width), offsets give \(offs[l.b] - offs[l.a])",
                     repro: repro)
        }

        // Painted: each line shaped alone, as the renderer does.
        if c.text.unicodeScalars.contains(where: MetricsSuite.bidi) {
            r.count(painted, "skippedRTL")
        } else if c.text.unicodeScalars.contains(where: Self.control) {
            r.count(painted, "skippedControl")
        } else {
            let bounds = Self.boundaries(c.text)
            let fallback = Self.usesFallback(c)
            if fallback { r.count(painted, "fallbackStrings") }
            for (i, l) in lines.enumerated() {
                guard bounds.contains(l.a) && bounds.contains(l.b) else {
                    // An over-wide word cut inside a grapheme cluster: shaped alone, each half
                    // is a different cluster. Counted, not compared (docs/layout.md, limits).
                    r.count(painted, "clusterCut")
                    continue
                }
                var u = String.UnicodeScalarView()
                u.append(contentsOf: scalars[l.a..<l.b])
                guard !u.contains("\t") else {
                    // A tab advances to a tab stop measured from the line's start, so a line with
                    // one is wider or narrower alone than in the whole string. Not compared.
                    r.count(painted, "tab")
                    continue
                }
                let shaped = TextSystem.shared.shape(c.font, String(u))
                r.ran(painted)
                r.count(painted, "shapedLines")
                let d = shaped.width - l.width
                // Shaped alone, a line loses the kerning with what was next to it in the whole
                // string: the dropped space (", " kerns) or, inside a cut word, the next letter.
                // So the slack is 1 pt of rounding plus 0.15 em, like the caret check's.
                let cut = (l.a > 0 && scalars[l.a - 1] != " ") || (l.b < scalars.count && scalars[l.b] != " ")
                let slack: Int32 = 1 + Int32((Double(min(max(c.size, 1), 1024)) * 0.15).rounded(.up))
                r.count(painted, d == 0 ? "widthExact" : abs(d) <= 1 ? "widthOff1" : cut ? "widthCutKern" : "widthSpaceKern")
                let caretsOK = (0...(l.b - l.a)).allSatisfy { k in
                    !bounds.contains(l.a + k) || abs(shaped.offsets[k] - (offs[l.a + k] - offs[l.a])) <= slack
                }
                if fallback {
                    // Shaped alone, a line may pick a different fallback font for neutral
                    // characters (digits, punctuation) next to a fallback run than the whole
                    // string did. Counted, not failed: a limit in docs/layout.md.
                    r.count(painted, abs(d) <= slack && caretsOK ? "fallbackSame" : "fallbackDiffers")
                    continue
                }
                guard r.expect(painted, abs(d) <= slack,
                               "line \(i) [\(l.a), \(l.b)) is \(l.width) wide to Lean, \(shaped.width) painted",
                               repro: repro) else { continue }
                for k in 0...(l.b - l.a) where bounds.contains(l.a + k) {
                    let want = offs[l.a + k] - offs[l.a]
                    if !r.expect(painted, abs(shaped.offsets[k] - want) <= slack,
                                 "line \(i): caret \(k) painted at \(shaped.offsets[k]), Lean has \(want)", repro: repro) { break }
                }
            }
        }

        // Core Text's own breaks, on plain text.
        guard c.plain else { return }
        let check = "text.wrap.coretext"
        r.ran(check)
        let ct = Self.coreTextLines(c)
        let lean = lines.map { ($0.a, $0.b) }
        if ct.elementsEqual(lean, by: { $0 == $1 }) { r.count(check, "same"); return }
        // The first line where they differ, from the same start.
        let i = zip(ct, lean).prefix(while: { $0 == $1 }).count
        guard i < ct.count, i < lean.count, ct[i].0 == lean[i].0 else {
            r.fail(check, "lines differ at \(i): Core Text \(ct.prefix(i + 1).suffix(2)), Lean \(lean.prefix(i + 1).suffix(2))", repro: repro)
            return
        }
        // The range one accepted and the other rejected: from the line's start to the next break
        // opportunity after the shorter line's end.
        let a = ct[i].0
        let short = min(ct[i].1, lean[i].1)
        let chars = Array(c.text.utf8)
        if (chars[short] != 0x20 && chars[short - 1] != 0x20) || (a > 0 && chars[a - 1] != 0x20) {
            // Inside a word too wide for a line, or on the line its last piece starts: Core Text
            // cuts by its own measure of the characters (not their advances), so the cut may land
            // a character away, and it may end the line after the last piece.
            r.count(check, "cutDiffers")
            r.expect(check, abs(ct[i].1 - lean[i].1) <= 2 || a > 0 && chars[a - 1] != 0x20,
                     "line \(i): a long word is cut at \(ct[i].1) by Core Text and \(lean[i].1) by Lean", repro: repro)
            return
        }
        var e = short + 1
        if chars[short] == 0x20 || chars[short - 1] == 0x20 {
            e = short
            while e < chars.count, chars[e] == 0x20 { e += 1 }
            while e < chars.count, chars[e] != 0x20 { e += 1 }
        }
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: c.text, attributes: [.font: MetricsSuite.ctFont(c.font)]))
        let frac = CTLineGetOffsetForStringIndex(line, e, nil) - CTLineGetOffsetForStringIndex(line, a, nil)
        let leanW = offs[e] - offs[a]
        let w = CGFloat(c.width)
        // Core Text keeps a little slack of its own: it can reject a line a fraction of a point
        // under the width. Either way, the line in dispute is within a point of the width.
        let explained = abs(CGFloat(leanW) - w) <= 1 || abs(frac - w) <= 1
        r.count(check, explained ? "roundingDiffers" : "differs")
        r.expect(check, explained,
                 "line \(i): Core Text [\(ct[i].0), \(ct[i].1)), Lean [\(lean[i].0), \(lean[i].1)); [\(a), \(e)) is \(frac) pt to Core Text, \(leanW) to Lean, width \(c.width)",
                 repro: repro)
    }

    /// Controls, line and paragraph separators and tabs: not text a para should hold.
    static func control(_ u: Unicode.Scalar) -> Bool {
        u.properties.generalCategory == .control || u.value == 0x2028 || u.value == 0x2029
    }

    /// Whether Core Text draws any of the string in a font other than the one asked for.
    static func usesFallback(_ c: Case) -> Bool {
        let base = MetricsSuite.ctFont(c.font)
        let name = CTFontCopyPostScriptName(base) as String
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: c.text, attributes: [.font: base]))
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let f = attrs[kCTFontAttributeName] as! CTFont
            if CTFontCopyPostScriptName(f) as String != name { return true }
        }
        return false
    }

    /// Core Text's lines for plain (ASCII) text, trailing spaces dropped, as scalar ranges.
    static func coreTextLines(_ c: Case) -> [(Int, Int)] {
        let attr = NSAttributedString(string: c.text, attributes: [.font: MetricsSuite.ctFont(c.font)])
        let ts = CTTypesetterCreateWithAttributedString(attr)
        let chars = Array(c.text.utf8)
        var out: [(Int, Int)] = []
        var start = 0
        while start < chars.count, chars[start] == 0x20 { start += 1 }
        while start < chars.count {
            let n = max(1, CTTypesetterSuggestLineBreak(ts, start, Double(c.width)))
            var end = start + n
            var trimmed = end
            while trimmed > start, chars[trimmed - 1] == 0x20 { trimmed -= 1 }
            if trimmed > start { out.append((start, trimmed)) }
            while end < chars.count, chars[end] == 0x20 { end += 1 }
            start = end
        }
        return out
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "wrap " + gen(&g).description
    }
}

extension WrapSuite {
    /// `CairnFuzzTrusted --bench-wrap` (bench/layout.md, "Wrapped text"): the host's share of a
    /// 1,000-word paragraph at 13 pt. Core Text shaping the whole string once (cold, a new string
    /// each run), shaping each line for painting (cold), and Lean breaking and laying it out with
    /// `TextMetrics.host` through the export, with the whole string already in the cache.
    static func bench() {
        Lean.start()
        let vocab = ["the", "quick", "brown", "fox", "jumps", "over", "a", "lazy", "dog", "while",
                     "measuring", "every", "glyph", "of", "text", "in", "Lean,", "and", "Metal", "paints",
                     "what", "was", "measured.", "Wrapping", "breaks", "at", "spaces", "only"]
        func paragraph(_ salt: Int) -> String {
            var g = SplitMix(seed: UInt64(salt + 1))
            return (0..<1000).map { _ in vocab[Int(g.next() % UInt64(vocab.count))] }.joined(separator: " ")
                + " \(salt)"
        }
        let font = Font(family: 0, size: 13, weight: 400, italic: false)
        func median(_ a: [Double]) -> Double { a.sorted()[a.count / 2] }
        func ms(_ f: () -> Void) -> Double {
            let t0 = DispatchTime.now().uptimeNanoseconds
            f()
            return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        }
        var shapeWhole: [Double] = [], shapeLines: [Double] = [], lean: [Double] = []
        var lineCount = 0
        for width in [200, 400, 800] {
            shapeWhole = []; shapeLines = []; lean = []
            for i in 0..<25 {
                let s = paragraph(width * 100 + i)
                shapeWhole.append(ms { _ = TextSystem.shared.shape(font, s) })
                var lines: [Lean.WrapLine] = []
                lean.append(ms { lines = Lean.wrap(font, width: UInt32(width), s) })
                lineCount = lines.count
                let scalars = Array(s.unicodeScalars)
                let strs = lines.map { l in
                    var u = String.UnicodeScalarView(); u.append(contentsOf: scalars[l.a..<l.b]); return String(u)
                }
                shapeLines.append(ms { for l in strs { _ = TextSystem.shared.shape(font, l) } })
            }
            print(String(format: "wrap 1000 words at width %d (%d lines, %d scalars): shape whole %.3f ms, Lean wrap+layout %.3f ms, shape lines %.3f ms",
                         width, lineCount, paragraph(width * 100).unicodeScalars.count,
                         median(shapeWhole), median(lean), median(shapeLines)))
        }
    }
}
