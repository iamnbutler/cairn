import AppKit
import CairnFrame
import Metal
import QuartzCore
import Testing
@testable import CairnHost

/// A focused text field with Lean's edit semantics for the input-method events, and a switch to
/// make it disagree with the host's shadow.
final class EchoFieldCore: AppCore, @unchecked Sendable {
    private let lock = NSLock()
    private var text: [Unicode.Scalar] = Array("a😀b".unicodeScalars)
    private var sel = 3..<3
    private var marked: Range<Int>?
    private var received: [Event] = []
    var ignoreEdits = false

    var events: [Event] { lock.withLock { received } }

    func start(size: Size, scalePercent: UInt32) {}

    private func replace(_ r: Range<Int>, _ s: String) -> Int {
        let lo = min(r.lowerBound, text.count), hi = min(max(r.upperBound, lo), text.count)
        text.replaceSubrange(lo..<hi, with: s.unicodeScalars)
        return lo
    }

    func step(_ events: [Event]) {
        lock.withLock {
            received += events
            guard !ignoreEdits else { return }
            for e in events {
                switch e {
                case let .insertText(s, r):
                    let lo = replace(r.map { Int($0.start)..<Int($0.end) } ?? marked ?? sel, s)
                    marked = nil
                    sel = (lo + s.unicodeScalars.count)..<(lo + s.unicodeScalars.count)
                case let .setMarked(s, a, n, r):
                    let lo = replace(r.map { Int($0.start)..<Int($0.end) } ?? marked ?? sel, s)
                    let len = s.unicodeScalars.count
                    marked = len == 0 ? nil : lo..<(lo + len)
                    sel = (lo + Int(a))..<(lo + Int(a + n))
                case .unmark: marked = nil
                default: break
                }
            }
        }
    }

    func frame() throws -> Frame {
        lock.withLock {
            var u = String.UnicodeScalarView(); u.append(contentsOf: text)
            let input = textInput(String(u), UInt32(sel.lowerBound), UInt32(sel.upperBound),
                                  marked: marked.map { (UInt32($0.lowerBound), UInt32($0.upperBound)) })
            return Frame(size: Size(w: 200, h: 100), draws: [], ax: [], textInput: input, cursor: .text, effects: [])
        }
    }
}

/// An app with no text field that records what it receives.
final class KeyLogCore: AppCore, @unchecked Sendable {
    private let lock = NSLock()
    private var received: [Event] = []
    var events: [Event] { lock.withLock { received } }
    func start(size: Size, scalePercent: UInt32) {}
    func step(_ events: [Event]) { lock.withLock { received += events } }
    func frame() throws -> Frame {
        Frame(size: Size(w: 200, h: 100), draws: [], ax: [], textInput: nil, cursor: .arrow, effects: [])
    }
}

final class TestRenderer: FrameRenderer {
    let device = MTLCreateSystemDefaultDevice()!
    func configure(_ layer: CAMetalLayer) { layer.device = device }
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {}
}

@MainActor
@Suite(.serialized) struct HostViewTextInputTests {
    func make(_ core: EchoFieldCore) -> HostView {
        let engine = Engine(size: Size(w: 200, h: 100), scalePercent: 200) { core }
        let view = HostView(engine: engine, renderer: TestRenderer(), size: NSSize(width: 200, height: 100))
        engine.start()
        settle(view)
        return view
    }

    func settle(_ view: HostView) {
        _ = view.engine.wait(through: view.engine.lastSeq)
        view.applyLatestFrame()
    }

    @Test func compositionRoundTrip() {
        let core = EchoFieldCore()
        let view = make(core)
        defer { view.engine.stop() }
        // "a😀b", caret at the end: UTF-16 offset 4.
        #expect(view.selectedRange() == NSRange(location: 4, length: 0))
        #expect(view.markedRange().location == NSNotFound)

        // Answers come from the shadow at once, before Lean has run.
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText())
        #expect(view.markedRange() == NSRange(location: 4, length: 1))
        #expect(view.selectedRange() == NSRange(location: 5, length: 0))

        view.insertText("日", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.hasMarkedText())
        #expect(view.attributedSubstring(forProposedRange: NSRange(location: 0, length: 5), actualRange: nil)?.string == "a😀b日")

        settle(view)
        #expect(view.shadowDivergences.isEmpty)
        #expect(view.textShadow.state?.text == "a😀b日")
        #expect(core.events.contains(.setMarked("に", selStart: 1, selLen: 0, replacing: nil)))
    }

    @Test func replacementRangeSplittingASurrogateIsSnapped() {
        let core = EchoFieldCore()
        let view = make(core)
        defer { view.engine.stop() }
        // UTF-16 2..<3 starts inside 😀; it becomes scalar range 1..<2 (the whole emoji).
        view.insertText("x", replacementRange: NSRange(location: 2, length: 1))
        settle(view)
        #expect(core.events.last == .insertText("x", replacing: ScalarRange(start: 1, end: 2)))
        #expect(view.textShadow.state?.text == "axb")
        #expect(view.shadowDivergences.isEmpty)
    }

    @Test func outOfBoundsReplacementIsClamped() {
        let core = EchoFieldCore()
        let view = make(core)
        defer { view.engine.stop() }
        view.insertText("!", replacementRange: NSRange(location: 99, length: 5))
        settle(view)
        #expect(core.events.last == .insertText("!", replacing: ScalarRange(start: 3, end: 3)))
        #expect(view.textShadow.state?.text == "a😀b!")
    }

    @Test func divergenceIsRecordedAndLeanWins() {
        let core = EchoFieldCore()
        let view = make(core)
        defer { view.engine.stop() }
        core.ignoreEdits = true
        view.insertText("z", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.textShadow.state?.text == "a😀bz")
        settle(view)
        #expect(view.shadowDivergences.count == 1)
        #expect(view.textShadow.state?.text == "a😀b")
    }

    static func keyEvent(_ s: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: hostNow(), windowNumber: 0,
                         context: nil, characters: s, charactersIgnoringModifiers: s, isARepeat: false, keyCode: 0)!
    }

    // Accessibility tools type with synthesized key events (keyCode 0, the text in the event's
    // Unicode string): one per character, back to back, or several characters in one. Both must
    // land whole, as they do in an NSTextView.
    @Test func synthesizedTypingLandsWhole() {
        let core = EchoFieldCore()
        let view = make(core)
        defer { view.engine.stop() }
        view.keyDown(with: Self.keyEvent("Walk to"))
        for c in " the cairn" { view.keyDown(with: Self.keyEvent(String(c))) }
        #expect(view.textShadow.state?.text == "a😀bWalk to the cairn")
        settle(view)
        #expect(view.textShadow.state?.text == "a😀bWalk to the cairn")
        #expect(view.shadowDivergences.isEmpty)
        #expect(core.events.first == .insertText("Walk to", replacing: nil))
    }

    @Test func synthesizedTypingWithoutAFieldIsEveryKey() {
        let core = KeyLogCore()
        let engine = Engine(size: Size(w: 200, h: 100), scalePercent: 200) { core }
        let view = HostView(engine: engine, renderer: TestRenderer(), size: NSSize(width: 200, height: 100))
        engine.start()
        defer { engine.stop() }
        settle(view)
        #expect(!view.textActive)
        view.keyDown(with: Self.keyEvent("Hi!"))
        settle(view)
        #expect(core.events == [.key(.char("h"), Mods()), .key(.char("i"), Mods()), .key(.char("!"), Mods())])
    }

    @Test func selectedRangeIsNeverNotFound() {
        let core = EchoFieldCore()
        let engine = Engine(size: Size(w: 200, h: 100), scalePercent: 200) { core }
        let view = HostView(engine: engine, renderer: TestRenderer(), size: NSSize(width: 200, height: 100))
        // No frame yet, so no field.
        #expect(view.selectedRange() == NSRange(location: 0, length: 0))
    }
}
