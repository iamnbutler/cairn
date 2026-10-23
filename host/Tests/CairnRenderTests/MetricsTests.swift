import CairnFrame
@testable import CairnRender
import CoreText
import Foundation
import Testing

let sampleFonts: [Font] = [
    Font(), Font(weight: 700), Font(size: 11, weight: 300), Font(size: 17, weight: 600, italic: true),
    Font(family: 1), Font(family: 1, weight: 700, italic: true), Font(size: 24, weight: 800), Font(size: 40),
]

let sampleStrings: [String] = [
    "", " ", "a", "Hello, world", "AVATAR", "AV", "fi ffl", "café", "e\u{301}x", "naïve",
    "😀", "a👨‍👩‍👧b", "👍🏽 ok", "你好世界", "こんにちは", "한국어", "混合 mixed ✨",
    "abאבc", "عربي", "tab\there", "\u{FEFF}bom", "trailing   ", "0123456789", "\u{0}nul",
]

/// The C ABI, called the way the Lean glue calls it.
func cMetrics(_ f: Font, _ s: String, cap: Int? = nil) -> (count: Int32, values: [Int32]) {
    var bytes = Array(s.utf8)
    let cap = cap ?? s.unicodeScalars.count + 3
    var out = [Int32](repeating: -7, count: max(cap, 1))
    let n = cairn_text_metrics(f.family, f.size, f.weight, f.italic ? 1 : 0, &bytes, bytes.count, &out, cap)
    return (n, Array(out.prefix(min(cap, Int(n)))))
}

@Suite struct MetricsTests {
    /// `TextMetrics.Valid`, checked directly on the host's output for every sample.
    @Test(arguments: sampleFonts) func valid(_ f: Font) {
        for s in sampleStrings {
            let (n, v) = cMetrics(f, s)
            let scalars = s.unicodeScalars.count
            #expect(Int(n) == scalars + 3, "\(s.debugDescription)")
            let offsets = Array(v.dropFirst(2))
            #expect(offsets.count == scalars + 1)
            #expect(offsets.first == 0)
            #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 }, "\(s.debugDescription): \(offsets)")
            #expect(v[0] >= 0 && v[1] >= 0)
        }
    }

    @Test func abiReportsSizeWhenCapIsShort() {
        let (n, v) = cMetrics(Font(), "Hello", cap: 4)
        #expect(n == 8)
        #expect(v.count == 4)
        let (n0, _) = cMetrics(Font(), "Hello", cap: 0)
        #expect(n0 == 8)
    }

    @Test func invalidUTF8IsRepaired() {
        var bytes: [UInt8] = [0x61, 0xff, 0x62]
        var out = [Int32](repeating: 0, count: 8)
        let n = cairn_text_metrics(0, 13, 400, 0, &bytes, 3, &out, 8)
        #expect(n == 6)  // "a\u{FFFD}b": three scalars
    }

    /// Every caret comes from one CTLine: kerning shows ("AV" caret at 1 is less than "A" alone).
    @Test func offsetsComeFromOneLine() {
        let f = Font(size: 40)
        let av = TextSystem.shared.shape(f, "AV").offsets
        let a = TextSystem.shared.shape(f, "A").offsets
        #expect(av[1] < a[1], "kerned caret \(av[1]) vs prefix width \(a[1])")
    }

    /// Scalar boundaries inside a cluster report the cluster's end; never 0 from a mid-surrogate query.
    @Test func clustersAndSurrogates() {
        let o = TextSystem.shared.shape(Font(), "a👨‍👩‍👧b").offsets
        // scalars: a, man, zwj, woman, zwj, girl, b → 8 offsets
        #expect(o.count == 8)
        #expect(o[1] > 0)
        #expect(Set(o[2...6]).count == 1, "inside the ZWJ cluster: \(o)")
        let e = TextSystem.shared.shape(Font(), "😀😀").offsets
        #expect(e.count == 3 && e[1] > 0 && e[2] > e[1], "\(e)")
    }

    /// The fast path in `TextSystem.shape`: on a line with no right-to-left run, the leading-edge
    /// caret CTLineEnumerateCaretOffsets reports at a UTF-16 index is CTLineGetOffsetForStringIndex
    /// there. (Checked on 158,000 random strings when it was introduced; these keep it honest.)
    @Test(arguments: sampleFonts) func enumeratedCaretsAreTheIndexedOnes(_ f: Font) {
        let extra = ["=\u{F883}E", "x\u{E000}\u{F8FF}y", "a\u{0}", "\u{93F}\u{1F3FB}\\x", "AV To. W,y",
                     "ffi fl", "ᚠᛇ 𐀀", "1️⃣ 🇺🇸🇬🇧", String(repeating: "lorem ipsum ", count: 40)]
        for s in sampleStrings + extra {
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: s, attributes: [.font: TextSystem.shared.ctFont(f)]))
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            if runs.contains(where: { CTRunGetStatus($0).contains(.rightToLeft) }) { continue }
            var seen = Set<Int>()
            var pairs: [(idx: Int, enumerated: Double)] = []
            CTLineEnumerateCaretOffsets(line) { off, idx, leading, _ in
                if leading, seen.insert(idx).inserted { pairs.append((idx, off)) }
            }
            for p in pairs {
                let x = Double(CTLineGetOffsetForStringIndex(line, p.idx, nil))
                #expect(p.enumerated == x, "\(f) \(s.debugDescription) at \(p.idx): enumerated \(p.enumerated), indexed \(x)")
            }
        }
    }

    /// The rounding rule: ⌈x − 1/256⌉, monotone, never below the exact advance by more than 1/256.
    @Test func rounding() {
        #expect(TextSystem.round(0) == 0)
        #expect(TextSystem.round(20.000001) == 20)
        #expect(TextSystem.round(20.01) == 21)
        #expect(TextSystem.round(-3) == 0)
        #expect(TextSystem.round(.nan) == 0)
        var prev: Int32 = 0
        for i in 0..<10_000 {
            let r = TextSystem.round(CGFloat(i) * 0.0137)
            #expect(r >= prev); prev = r
        }
    }

    /// Lean's box for a text draw: x from origin to origin + width (last offset), y from
    /// baseline − ascent to baseline + descent. Every glyph's advance lies inside it horizontally.
    @Test(arguments: sampleFonts) func advancesInsideBox(_ f: Font) {
        for s in sampleStrings where !s.isEmpty {
            let line = TextSystem.shared.shape(f, s)
            for run in line.runs {
                for i in 0..<run.glyphs.count {
                    let x0 = run.positions[i].x, x1 = x0 + run.advances[i].width
                    #expect(x0 >= -1.0 / 256 && x1 <= CGFloat(line.width) + 1.0 / 256,
                            "\(f) \(s.debugDescription) glyph \(i): \(x0)…\(x1) vs width \(line.width)")
                }
            }
        }
    }

    @Test func cacheReturnsTheSameLine() {
        let a = TextSystem.shared.shape(Font(), "cached")
        let b = TextSystem.shared.shape(Font(), "cached")
        #expect(a.offsets == b.offsets)
        #expect(a.runs.count == b.runs.count)
    }

    @Test func fontMapping() {
        #expect(Fonts.weight(400) == .regular)
        #expect(Fonts.weight(449) == .regular)
        #expect(Fonts.weight(450) == .medium)
        #expect(Fonts.weight(0) == .ultraLight)
        #expect(Fonts.weight(5000) == .black)
        let mono = Fonts.make(Font(family: 1))
        #expect(CTFontGetSymbolicTraits(mono).contains(.traitMonoSpace))
        let italic = Fonts.make(Font(italic: true))
        #expect(CTFontGetSymbolicTraits(italic).contains(.traitItalic))
        #expect(CTFontGetSize(Fonts.make(Font(size: 0))) == 1)   // not Core Text's default 12
        #expect(CTFontGetSize(Fonts.make(Font(size: 99999))) == 1024)
        let bold = Fonts.make(Font(weight: 700))
        #expect(CTFontGetSymbolicTraits(bold).contains(.traitBold))
    }
}
