import AppKit
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

/// A field whose text is scrolled 260 points left: the text draw's origin is outside the field.
final class ScrolledFieldCore: AppCore, @unchecked Sendable {
    func start(size: Size, scalePercent: UInt32) {}
    func step(_ events: [Event]) {}
    func frame() throws -> Frame {
        let text = String(repeating: "w", count: 40)
        let origin = Point(x: -250, y: 30)
        let field = Rect(x: 10, y: 10, w: 180, h: 30)
        return Frame(size: Size(w: 200, h: 100),
                     draws: [.pushClip(field), .text(origin: origin, font: Font(), color: Color(r: 0, g: 0, b: 0), string: text), .popClip],
                     textInput: TextInput(control: ControlRef(claim: 1), rect: field, caret: Rect(x: 185, y: 16, w: 1, h: 16),
                                          text: text, selection: (40, 40), marked: nil, textOrigin: origin),
                     cursor: .text)
    }
}

@MainActor
@Suite(.serialized) struct ScrolledFieldTests {
    /// The input-method geometry measures from the frame's textOrigin, so it still works when
    /// the text is scrolled (it used to look for a text draw starting inside the field and,
    /// finding none, answer NSNotFound).
    @Test func characterIndexAndFirstRectInAScrolledField() {
        let engine = Engine(size: Size(w: 200, h: 100), scalePercent: 200) { ScrolledFieldCore() }
        let view = HostView(engine: engine, renderer: TestRenderer(), size: NSSize(width: 200, height: 100))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless],
                              backing: .buffered, defer: true)
        window.contentView = view
        engine.start()
        defer { engine.stop() }
        _ = engine.wait(through: engine.lastSeq)
        view.applyLatestFrame()
        let r = view.firstRect(forCharacterRange: NSRange(location: 30, length: 5), actualRange: nil)
        #expect(r.width > 0)
        let i = view.characterIndex(for: NSPoint(x: r.minX, y: r.midY))
        #expect(i == 30)
    }
}
