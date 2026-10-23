import CairnFrame
import Testing
@testable import CairnHost

/// Minimal repros of disagreements `cairn-fuzz-trusted` found (docs/fuzz.md, "Trusted base").
@Suite struct HostFuzzRegressionTests {
    /// Lean's single-line field stores each line break as a space (`Field.clean`); the shadow
    /// kept them, so its prediction diverged from Lean's frame. Fixed: the shadow flattens too.
    @Test func shadowFlattensLineBreaks() {
        var s = TextInputShadow()
        _ = s.frameArrived(textInput("", 0, 0), throughSeq: 0)
        s.insert("a\nb\r\u{2028}c", replacing: nil, seq: 1)
        #expect(s.state?.text == "a b  c")
        s.setMarked("x\u{85}", selection: 2..<2, replacing: nil, seq: 2)
        #expect(s.state?.text == "a b  cx ")
        // Lean's frame agrees, so this is no divergence.
        guard case .adopted = s.frameArrived(textInput("a b  cx ", 8, 8, marked: (6, 8)), throughSeq: 2) else {
            Issue.record("diverged"); return
        }
    }
}
