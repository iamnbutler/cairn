import AppKit
import CairnFrame
import CairnRender

/// `NSTextInputClient`, answered from the host's shadow of the focused field (see
/// `TextInputShadow`) and the last frame's geometry. Every AppKit range is UTF-16 and goes
/// through `TextIndex` to become Lean's scalar indices.
extension HostView: @preconcurrency NSTextInputClient {
    private static func string(_ s: Any) -> String {
        (s as? NSAttributedString)?.string ?? (s as? String) ?? ""
    }

    private var textShadowIndex: TextIndex { TextIndex(textShadow.state?.text ?? "") }

    private func inputTime() -> Double { currentKeyEvent.map { min($0.timestamp, hostNow()) } ?? hostNow() }

    /// A replacement range in the field, or nil for "the marked text, else the selection".
    private func replacement(_ r: NSRange) -> Range<Int>? {
        r.location == NSNotFound ? nil : textShadowIndex.scalars(r)
    }

    private static func scalarRange(_ r: Range<Int>?) -> ScalarRange? {
        r.map { ScalarRange(start: UInt32($0.lowerBound), end: UInt32($0.upperBound)) }
    }

    // MARK: Edits: sent to Lean, and applied to the textShadow at once

    public func insertText(_ string: Any, replacementRange: NSRange) {
        let s = Self.string(string)
        let replace = replacement(replacementRange)
        let seq = send([.insertText(s, replacing: Self.scalarRange(replace))], time: inputTime())
        textShadow.insert(s, replacing: replace, seq: seq)
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let s = Self.string(string)
        let ix = TextIndex(s)
        let sel = ix.scalars(selectedRange) ?? (ix.scalarCount..<ix.scalarCount)
        let replace = replacement(replacementRange)
        let seq = send([.setMarked(s, selStart: UInt32(sel.lowerBound), selLen: UInt32(sel.count),
                                   replacing: Self.scalarRange(replace))], time: inputTime())
        textShadow.setMarked(s, selection: sel, replacing: replace, seq: seq)
    }

    public func unmarkText() {
        let seq = send([.unmark], time: inputTime())
        textShadow.unmark(seq: seq)
    }

    public override func doCommand(by selector: Selector) {
        let name = NSStringFromSelector(selector)
        if let e = KeyMapping.command(name) {
            sendEditing([e], time: inputTime())
        } else if name == "noop:", let e = currentKeyEvent,
                  !e.modifierFlags.intersection([.command, .control]).isEmpty,
                  let ev = KeyMapping.key(keyCode: e.keyCode, charactersIgnoringModifiers: e.charactersIgnoringModifiers,
                                          mods: KeyMapping.mods(e.modifierFlags)) {
            sendEditing([ev], time: min(e.timestamp, hostNow()))  // an unbound shortcut: Lean may want it
        }
        // Anything else is swallowed: no beep, Lean decides what keys mean.
    }

    // MARK: Queries

    /// Never NSNotFound: dictation needs to know where text goes. With no field, an empty range
    /// at 0.
    public func selectedRange() -> NSRange {
        guard let st = textShadow.state else { return NSRange(location: 0, length: 0) }
        return textShadowIndex.nsRange(scalars: st.selection.lowerBound, st.selection.upperBound)
    }

    public func markedRange() -> NSRange {
        guard let m = textShadow.state?.marked else { return NSRange(location: NSNotFound, length: 0) }
        return textShadowIndex.nsRange(scalars: m.lowerBound, m.upperBound)
    }

    public func hasMarkedText() -> Bool { textShadow.state?.marked != nil }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let st = textShadow.state, let r = textShadowIndex.scalars(range) else { return nil }
        let u = textShadowIndex.nsRange(scalars: r.lowerBound, r.upperBound)
        actualRange?.pointee = u
        return NSAttributedString(string: (st.text as NSString).substring(with: u))
    }

    /// Screen rect for a range: x from the same shaped line Lean measures with
    /// (`TextSystem.shape`, the renderer's and `cairn_text_metrics`'s), from the frame's
    /// `textOrigin`; y and height from the frame's caret. An empty range is a
    /// zero-width rect at that position (dictation draws its indicator there).
    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let f = shown?.frame.textInput, let st = textShadow.state else { return .zero }
        let ix = textShadowIndex
        let r = ix.scalars(range) ?? (st.selection.lowerBound..<st.selection.lowerBound)
        actualRange?.pointee = ix.nsRange(scalars: r.lowerBound, r.upperBound)
        var rect = f.caret.cg
        rect.size.width = 0
        if let (origin, font) = fieldText(f) {
            let offsets = TextSystem.shared.shape(font, st.text).offsets
            func x(_ i: Int) -> CGFloat { CGFloat(offsets[min(max(i, 0), offsets.count - 1)]) }
            rect.origin.x = origin.x + x(r.lowerBound)
            rect.size.width = x(r.upperBound) - x(r.lowerBound)
        }
        return screenRect(rect)
    }

    /// The UTF-16 offset of the scalar boundary nearest a screen point in the field.
    public func characterIndex(for point: NSPoint) -> Int {
        guard let f = shown?.frame.textInput, let st = textShadow.state, let window else { return NSNotFound }
        let p = convert(window.convertPoint(fromScreen: point), from: nil)
        guard f.rect.cg.contains(p), let (origin, font) = fieldText(f) else { return NSNotFound }
        let offsets = TextSystem.shared.shape(font, st.text).offsets
        let dx = p.x - origin.x
        let i = offsets.indices.min { abs(CGFloat(offsets[$0]) - dx) < abs(CGFloat(offsets[$1]) - dx) } ?? 0
        return textShadowIndex.utf16(i)
    }

    public func windowLevel() -> Int { window?.level.rawValue ?? 0 }

    public func baselineDeltaForCharacter(at anIndex: Int) -> CGFloat { 0 }

    /// Where and in which font the field's text is drawn. The origin is the frame's
    /// `textOrigin` (the left end of the baseline after horizontal scroll, docs/frame.md); the
    /// font is that of the text draw at that origin, preferring the one showing the field's
    /// text (an empty field may draw its placeholder there, in the same font).
    ///
    /// The origin used to be found by searching for a text draw whose baseline starts inside
    /// the field, which fails once the text scrolls left: `characterIndex` then answered
    /// NSNotFound and `firstRect` collapsed to the caret (found by cairn-fuzz-trusted).
    private func fieldText(_ f: TextInput) -> (CGPoint, Font)? {
        let origin = CGPoint(x: CGFloat(f.textOrigin.x), y: CGFloat(f.textOrigin.y))
        var font: Font?
        for case let .text(o, ft, _, s) in shown?.frame.draws ?? [] where o == f.textOrigin {
            if s == f.text { font = ft; break }
            if font == nil { font = ft }
        }
        return (origin, font ?? Font(family: 0, size: 13, weight: 400, italic: false))
    }

    // MARK: Frames

    /// Reconciles the shadow with a new frame and keeps AppKit's text input in step.
    func textInputDidChange(_ p: Published, previousFrame: TextInput?) {
        var discard = false
        let wasActive = textActive
        switch textShadow.frameArrived(p.frame.textInput, throughSeq: p.throughSeq) {
        case .pending:
            break
        case .adopted(let external, let previous):
            // Lean ended or moved the composition on its own (a click elsewhere, a blur, Escape):
            // the input method must drop its copy.
            discard = external && previous?.marked != nil
        case .diverged(let d):
            recordDivergence(d)
            discard = d.expected?.marked != nil && d.expected?.marked != d.actual?.marked
        }
        if discard { super.inputContext?.discardMarkedText() }
        if discard || previousFrame != p.frame.textInput { inputContext?.invalidateCharacterCoordinates() }
        // `inputContext` is nil while no field is focused, and AppKit only re-reads it when the
        // window updates: without this the input method never engages after a focus change and
        // keys arrive as plain characters (no IME).
        if wasActive != textActive {
            if textActive { super.inputContext?.activate() } else { super.inputContext?.deactivate() }
            NSApp.updateWindows()
        }
    }
}
