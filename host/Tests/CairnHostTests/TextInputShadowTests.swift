import CairnFrame
import Testing
@testable import CairnHost

func textInput(_ text: String, _ a: UInt32, _ b: UInt32, marked: (UInt32, UInt32)? = nil,
               control: ControlRef = ControlRef(claim: 1)) -> TextInput {
    let r = Rect(x: 0, y: 0, w: 100, h: 20)
    return TextInput(control: control, rect: r, caret: r, text: text, selection: (a, b),
                     marked: marked.map { (start: $0.0, end: $0.1) })
}

@Suite struct TextInputShadowTests {
    func focused(_ text: String, _ a: UInt32, _ b: UInt32) -> TextInputShadow {
        var s = TextInputShadow()
        _ = s.frameArrived(textInput(text, a, b), throughSeq: 0)
        return s
    }

    @Test func clampsLeanState() {
        let f = FieldState(textInput("ab", 5, 1, marked: (2, 2)))
        #expect(f.selection == 1..<2)
        #expect(f.marked == nil)  // an empty mark is no mark
    }

    @Test func compositionReplacesSelectionThenMarked() {
        var s = focused("abc", 1, 2)
        s.setMarked("に", selection: 1..<1, replacing: nil, seq: 1)
        #expect(s.state?.text == "aにc")
        #expect(s.state?.marked == 1..<2)
        #expect(s.state?.selection == 2..<2)
        s.setMarked("にほ", selection: 2..<2, replacing: nil, seq: 2)
        #expect(s.state?.text == "aにほc")
        #expect(s.state?.marked == 1..<3)
        s.insert("日本", replacing: nil, seq: 3)
        #expect(s.state?.text == "a日本c")
        #expect(s.state?.marked == nil)
        #expect(s.state?.selection == 3..<3)
    }

    @Test func emptyMarkEndsComposition() {
        var s = focused("ab", 2, 2)
        s.setMarked("x", selection: 1..<1, replacing: nil, seq: 1)
        s.setMarked("", selection: 0..<0, replacing: nil, seq: 2)
        #expect(s.state?.text == "ab")
        #expect(s.state?.marked == nil)
        #expect(s.state?.selection == 2..<2)
    }

    @Test func explicitReplacement() {
        var s = focused("hello", 5, 5)
        s.insert("J", replacing: 0..<1, seq: 1)
        #expect(s.state?.text == "Jello")
        #expect(s.state?.selection == 1..<1)
    }

    @Test func unmarkKeepsText() {
        var s = focused("", 0, 0)
        s.setMarked("ka", selection: 2..<2, replacing: nil, seq: 1)
        s.unmark(seq: 2)
        #expect(s.state?.text == "ka")
        #expect(s.state?.marked == nil)
    }

    @Test func pendingUntilFrameCatchesUp() {
        var s = focused("", 0, 0)
        s.insert("a", replacing: nil, seq: 4)
        if case .pending = s.frameArrived(textInput("", 0, 0), throughSeq: 3) {} else { Issue.record("expected pending") }
        #expect(s.state?.text == "a")
    }

    @Test func agreeingFrameIsAdoptedQuietly() {
        var s = focused("", 0, 0)
        s.insert("a", replacing: nil, seq: 1)
        guard case .adopted(let external, _) = s.frameArrived(textInput("a", 1, 1), throughSeq: 1) else {
            Issue.record("expected adoption"); return
        }
        #expect(!external)
        #expect(s.checks == 1)
    }

    @Test func disagreeingFrameIsADivergence() {
        var s = focused("", 0, 0)
        s.insert("a", replacing: nil, seq: 1)
        guard case .diverged(let d) = s.frameArrived(textInput("", 0, 0), throughSeq: 1) else {
            Issue.record("expected divergence"); return
        }
        #expect(d.expected?.text == "a")
        #expect(d.actual?.text == "")
        #expect(s.state?.text == "")  // Lean wins
    }

    @Test func taintedPredictionIsNotChecked() {
        var s = focused("", 0, 0)
        s.insert("a", replacing: nil, seq: 1)
        s.taint(seq: 2)
        guard case .adopted(let external, _) = s.frameArrived(textInput("ab", 2, 2), throughSeq: 2) else {
            Issue.record("expected adoption"); return
        }
        #expect(external)
        #expect(s.checks == 0)
    }

    @Test func externalChangeIsReported() {
        var s = focused("ab", 0, 0)
        guard case .adopted(let external, _) = s.frameArrived(textInput("ab", 2, 2), throughSeq: 5) else {
            Issue.record("expected adoption"); return
        }
        #expect(external)
    }

    @Test func noFieldIgnoresEdits() {
        var s = TextInputShadow()
        s.insert("a", replacing: nil, seq: 1)
        #expect(s.state == nil)
    }
}
