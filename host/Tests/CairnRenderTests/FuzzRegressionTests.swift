import CairnFrame
import Testing
@testable import CairnRender

/// Minimal repros of what `cairn-fuzz-trusted` found in text metrics (docs/fuzz.md, "Trusted base").
@Suite struct RenderFuzzRegressionTests {
    let font = Font(family: 0, size: 20, weight: 400, italic: false)

    /// Core Text answers 0 for the caret before a trailing NUL; the running max then put the caret
    /// after "a" at 0, before the "a" it follows.
    @Test func caretBeforeATrailingControl() {
        let a = TextSystem.shared.shape(font, "a").offsets
        let line = TextSystem.shared.shape(font, "a\u{0}").offsets
        #expect(line == [0, a[1], a[1]])
        let mid = TextSystem.shared.shape(font, "a\u{0}b\u{0}").offsets
        #expect(mid[3] > mid[2], "\(mid)")
    }

    /// After a Devanagari vowel sign and a lone skin tone, Core Text answers 0 for every later
    /// caret, which made "\\" and "x" zero-width at the emoji's start.
    @Test func caretsAfterFallbackRuns() {
        let o = TextSystem.shared.shape(font, "\u{93F}\u{1F3FB}\\x").offsets
        #expect(o.count == 5)
        #expect(o[3] > o[2] && o[4] > o[3], "\(o)")
    }

    /// Core Text's carets on a tracked line sit half the tracking short of the next glyph, and
    /// beside a tab whose advance is just the tracking the caret after the next letter lands in
    /// its middle. A tracked line's carets are the pen's position after the glyphs before them.
    @Test func trackedCaretsFollowThePen() {
        for (f, text) in [(Font(family: 0, size: 20, weight: 400, italic: false, tracking: 500), "abc"),
                          (Font(family: 0, size: 20, weight: 400, italic: false, tracking: -500), "abc"),
                          (Font(family: 1, size: 312, weight: 600, italic: true, tracking: -156), "ab\there")] {
            let line = TextSystem.shared.shape(f, text)
            // Every glyph is one scalar here, in order: the pen after glyph k is offset k + 1.
            let pens: [Double] = line.runs.flatMap { r in zip(r.positions, r.advances).map { Double($0.x + $1.width) } }
            #expect(pens.count == text.unicodeScalars.count)
            for (k, x) in pens.enumerated() {
                let want = (x - 1.0 / 256).rounded(.up)
                #expect(Double(line.offsets[k + 1]) == max(want, Double(line.offsets[k])), "\(text) \(f.tracking): \(line.offsets)")
            }
        }
    }
}
