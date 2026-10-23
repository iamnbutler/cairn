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
}
