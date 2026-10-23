import AppKit
import CLean
import CairnFrame
import CairnHost
import CairnRender
import CairnTrustedLean
import Foundation
import Metal
import QuartzCore

/// A renderer that draws nothing: this suite reads frames, it never paints them.
final class NullRenderer: FrameRenderer {
    let device = MTLCreateSystemDefaultDevice()!
    func configure(_ layer: CAMetalLayer) { layer.device = device }
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {}
}

/// The host's `NSTextInputClient` (HostView) on a real Lean app that is one text field
/// (`Cairn.Fuzz.Trusted.fieldApp`: the runtime, `Field.apply`, `Frame.ofLaid`, Core Text
/// metrics), driven the way input methods drive it: insert, setMarked and unmark with UTF-16
/// ranges that are out of bounds or split surrogate pairs, editing commands, resizes. Checks:
///
/// - `text.shadow`: the host's prediction of each edit (TextInputShadow) is what Lean does;
/// - `text.input-client`: every range the client returns is in bounds and on scalar
///   boundaries, substrings are the text there, and after a frame, `selectedRange` and
///   `markedRange` are Lean's; `firstRect` of the caret is Lean's caret rect, and
///   `characterIndex` at a boundary's x returns that boundary.
///
/// The window is never shown; effects are swallowed by `effectHook`, so nothing reaches the
/// pasteboard or the speaker.
final class InputClientSuite: Suite {
    let name = "inputclient"
    let crashCheck = "text.input-client"
    let checks: [String: CheckInfo] = [
        "text.shadow": CheckInfo(
            title: "The host's text-input shadow predicts Lean's edits",
            trusted: ["host/Sources/CairnHost/TextInputShadow.swift", "host/Sources/CairnHost/TextInputClient.swift"],
            oracle: "Lean's Field.apply through the runtime (the next frame's textInput)"),
        "text.input-client": CheckInfo(
            title: "NSTextInputClient answers in bounds, on scalar boundaries, at Lean's geometry",
            trusted: ["host/Sources/CairnHost/TextInputClient.swift", "host/Sources/CairnHost/TextIndex.swift",
                      "host/Sources/CairnRender/TextSystem.swift"],
            oracle: "Lean's frame (textInput: text, selection, marked, caret rect) and Swift's string views"),
    ]

    func cases(for n: Int) -> Int { max(1, n / 5) }

    var view: HostView!
    var window: NSWindow!
    var engine: Engine!

    func setUp() {
        MainActor.assumeIsolated {
            let app = LeanApp(module: initialize_cairn_Cairn_Fuzz_Trusted_Export,
                              initialize: { cairn_tf_field_init($0, $1, $2) },
                              step: { cairn_tf_field_step($0, $1) },
                              frame: { cairn_tf_field_frame($0) },
                              codec: FrameV1Codec())
            engine = Engine(size: Size(w: 400, h: 60), scalePercent: 200) { LeanCore(app) }
            view = HostView(engine: engine, renderer: NullRenderer(), size: NSSize(width: 400, height: 60))
            view.effectHook = { _ in true }
            window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: true)
            window.contentView = view
            engine.start()
            settle()
        }
    }

    func settle() {
        _ = engine.wait(through: engine.lastSeq)
        MainActor.assumeIsolated { view.applyLatestFrame() }
    }

    enum Op {
        case insert(String, NSRange, attributed: Bool)
        case setMarked(String, sel: NSRange, NSRange, attributed: Bool)
        case unmark
        case command(String)
        case resize(Int)
        case settle
    }

    static let commands = ["moveLeft:", "moveRight:", "moveWordLeft:", "moveWordRight:",
                           "moveLeftAndModifySelection:", "moveRightAndModifySelection:",
                           "moveToBeginningOfLine:", "moveToEndOfLine:", "deleteBackward:", "deleteForward:",
                           "deleteWordBackward:", "selectAll:", "cancelOperation:"]

    /// An AppKit range over a string of `u` UTF-16 units: mostly NSNotFound (no replacement),
    /// else in range, past the end, or huge.
    static func range(_ g: inout SplitMix, _ u: Int, notFound: Int = 2) -> NSRange {
        g.weighted([
            (notFound, { _ in NSRange(location: NSNotFound, length: 0) }),
            (4, { g in let a = g.range(0, u); return NSRange(location: a, length: g.range(0, u - a)) }),
            (1, { g in NSRange(location: g.range(0, u + 3), length: g.elem([0, 1, 2, 5, Int.max / 2])) }),
        ])
    }

    func ops(_ g: inout SplitMix) -> (width: Int, [Op]) {
        // Ranges are drawn against a guess at the text length; anything goes, the client clamps.
        var guessU16 = 0
        var out: [Op] = []
        for _ in 0..<g.range(4, 24) {
            let op: Op = g.weighted([
                (8, { g in
                    let s = TextPool.string(&g)
                    defer { guessU16 += s.utf16.count }
                    return .insert(s, Self.range(&g, guessU16), attributed: g.chance(1, 4))
                }),
                (5, { g in
                    let s = TextPool.string(&g, maxParts: 4)
                    return .setMarked(s, sel: Self.range(&g, s.utf16.count, notFound: 0),
                                      Self.range(&g, guessU16, notFound: 6), attributed: g.chance(1, 4))
                }),
                (2, { _ in .unmark }),
                (3, { g in .command(g.elem(Self.commands)) }),
                (1, { g in .resize(g.elem([60, 120, 240, 400, 900])) }),
                (4, { _ in .settle }),
            ])
            out.append(op)
        }
        return (g.elem([120, 400, 900]), out)
    }

    func describe(_ op: Op) -> String {
        switch op {
        case let .insert(s, r, a): return "insertText(\(Dump.str(s))\(a ? " attributed" : ""), replacementRange: \(r))"
        case let .setMarked(s, sel, r, a):
            return "setMarkedText(\(Dump.str(s))\(a ? " attributed" : ""), selectedRange: \(sel), replacementRange: \(r))"
        case .unmark: return "unmarkText()"
        case let .command(c): return "doCommand(\(c))"
        case let .resize(w): return "resize width \(w)"
        case .settle: return "(frame)"
        }
    }

    /// UTF-16 offsets of the scalar boundaries of `s`.
    static func boundaries(_ s: String) -> Set<Int> {
        var b: Set<Int> = [0]
        var u = 0
        for c in s.unicodeScalars { u += c.utf16.count; b.insert(u) }
        return b
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        MainActor.assumeIsolated { runOnMain(&g, r) }
    }

    @MainActor func runOnMain(_ g: inout SplitMix, _ r: Recorder) {
        let (width, script) = ops(&g)
        _ = engine.restart(size: Size(w: Int32(width), h: 60), scalePercent: 200)
        view.setFrameSize(NSSize(width: width, height: 60))
        settle()
        var log: [String] = ["width \(width)"]
        var divergences = view.shadowDivergences.count
        let shadow = "text.shadow", client = "text.input-client"

        func context() -> String {
            "after " + log.suffix(8).joined(separator: "; ")
                + "; text \(Dump.str(view.textShadow.state?.text ?? "<no field>"))"
        }

        /// Bounds and boundaries of everything the client answers, from the shadow, at any time.
        func checkQueries() {
            guard let st = view.textShadow.state else { r.fail(client, "no field after \(context())"); return }
            let text = st.text as NSString
            let n = text.length
            let bs = Self.boundaries(st.text)
            func whole(_ x: NSRange) -> Bool { x.location >= 0 && NSMaxRange(x) <= n && bs.contains(x.location) && bs.contains(NSMaxRange(x)) }
            let sel = view.selectedRange()
            r.expect(client, sel.location != NSNotFound && whole(sel), "selectedRange \(sel) of \(n) units, \(context())")
            let marked = view.markedRange()
            if view.hasMarkedText() {
                r.expect(client, whole(marked), "markedRange \(marked) of \(n) units, \(context())")
            } else {
                r.expect(client, marked.location == NSNotFound, "markedRange \(marked) without marked text, \(context())")
            }
            let q = Self.range(&g, n, notFound: 1)
            var actual = NSRange(location: -7, length: -7)
            let sub = view.attributedSubstring(forProposedRange: q, actualRange: &actual)
            if q.location == NSNotFound {
                r.expect(client, sub == nil, "attributedSubstring(\(q)) is not nil, \(context())")
            } else if let sub {
                r.expect(client, whole(actual) && sub.string == text.substring(with: actual),
                         "attributedSubstring(\(q)) = \(Dump.str(sub.string)) actual \(actual), \(context())")
            } else {
                r.fail(client, "attributedSubstring(\(q)) is nil, \(context())")
            }
        }

        /// After a frame: the client agrees with Lean, and its geometry is Lean's.
        func checkFrame() {
            guard let t = view.shown?.frame.textInput else { r.fail(client, "no textInput in Lean's frame, \(context())"); return }
            let ix = TextIndex(t.text)
            let selLo = Int(min(t.selection.start, t.selection.end)), selHi = Int(max(t.selection.start, t.selection.end))
            r.expect(client, view.selectedRange() == ix.nsRange(scalars: selLo, selHi),
                     "selectedRange \(view.selectedRange()), Lean's selection \(t.selection), \(context())")
            let wantMarked = t.marked.flatMap { $0.start == $0.end ? nil : ix.nsRange(scalars: Int($0.start), Int($0.end)) }
            r.expect(client, (wantMarked == nil && view.markedRange().location == NSNotFound) || view.markedRange() == wantMarked,
                     "markedRange \(view.markedRange()), Lean's \(String(describing: t.marked)), \(context())")
            // firstRect at the caret is Lean's caret rect. The frame's selection is ordered, so
            // the caret is at one of its ends.
            func caretRect(_ i: Int) -> (NSRect, NSRect, NSRange) {
                var actual = NSRange()
                let u = ix.utf16(i)
                let screen = view.firstRect(forCharacterRange: NSRange(location: u, length: 0), actualRange: &actual)
                return (screen, view.convert(window.convertFromScreen(screen), from: nil), actual)
            }
            let ends = [selHi, selLo].map(caretRect)
            let hit = ends.firstIndex { Int32($0.1.minX.rounded()) == t.caret.x } ?? 0
            let (screen, local, actual0) = ends[hit]
            let caretIx = hit == 0 ? selHi : selLo
            let u = ix.utf16(caretIx)
            r.expect(client, actual0 == NSRange(location: u, length: 0), "firstRect actualRange \(actual0) for caret \(u), \(context())")
            r.expect(client, Int32(local.minX.rounded()) == t.caret.x && local.width == 0
                        && Int32(local.minY.rounded()) == t.caret.y && Int32(local.height.rounded()) == t.caret.h,
                     "firstRect at the selection's ends \(ends.map { $0.1 }), Lean's caret \(t.caret), \(context())")
            r.count(client, "caretRects")
            var actual = NSRange()
            // A random range: in bounds, whole scalars, width ≥ 0, x within the text's extent.
            let q = Self.range(&g, ix.utf16Count, notFound: 1)
            let qr = view.firstRect(forCharacterRange: q, actualRange: &actual)
            let bs = Self.boundaries(t.text)
            r.expect(client, qr.width >= 0 && actual.location >= 0 && NSMaxRange(actual) <= ix.utf16Count
                        && bs.contains(actual.location) && bs.contains(NSMaxRange(actual)),
                     "firstRect(\(q)) = \(qr) actual \(actual), \(context())")
            // characterIndex at the caret's own x inside the field returns a boundary with that x.
            let p = NSPoint(x: screen.minX, y: screen.midY)
            let ci = view.characterIndex(for: p)
            let inField = local.minX >= CGFloat(t.rect.x) && local.minX < CGFloat(t.rect.x + t.rect.w)
            if inField {
                let offsets = TextSystem.shared.shape(Font(), t.text).offsets
                let j = ix.scalar(ci)
                r.expect(client, ci != NSNotFound && bs.contains(ci) && offsets[j] == offsets[caretIx],
                         "characterIndex at the caret's x (\(screen.minX)) = \(ci), caret is \(u), \(context())")
                r.count(client, "characterIndexRoundTrips")
            }
            // Anywhere: NSNotFound or a boundary.
            let any = NSPoint(x: window.frame.minX + CGFloat(g.range(-20, Int(window.frame.width) + 20)),
                              y: window.frame.minY + CGFloat(g.range(-10, 70)))
            let ca = view.characterIndex(for: any)
            r.expect(client, ca == NSNotFound || bs.contains(ca), "characterIndex(\(any)) = \(ca), \(context())")
        }

        for op in script {
            log.append(describe(op))
            switch op {
            case let .insert(s, rr, a):
                view.insertText(a ? NSAttributedString(string: s) : s, replacementRange: rr)
            case let .setMarked(s, sel, rr, a):
                view.setMarkedText(a ? NSAttributedString(string: s) : s, selectedRange: sel, replacementRange: rr)
            case .unmark:
                view.unmarkText()
            case let .command(c):
                view.doCommand(by: NSSelectorFromString(c))
            case let .resize(w):
                view.setFrameSize(NSSize(width: w, height: 60))
            case .settle:
                settle()
                let d = view.shadowDivergences
                r.expect(shadow, d.count == divergences, "\(d.last.map { "\($0)" } ?? "") \(context())")
                divergences = d.count
                checkFrame()
            }
            checkQueries()
        }
        settle()
        let d = view.shadowDivergences
        r.expect(shadow, d.count == divergences, "\(d.last.map { "\($0)" } ?? "") \(context())")
        checkFrame()
        checkQueries()
        r.count(shadow, "edits", script.count)
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        let (w, script) = ops(&g)
        return "width \(w): " + script.map(describe).joined(separator: "; ")
    }
}
