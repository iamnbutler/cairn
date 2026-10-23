import AppKit
import CairnFrame
import CoreText

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

    /// Screen rect for a range: x from Core Text over the shadow's text with the field's font,
    /// anchored where the frame drew the field's text; y and height from the frame's caret. An
    /// empty range is a zero-width rect at that position (dictation draws its indicator there).
    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let f = shown?.frame.textInput, let st = textShadow.state else { return .zero }
        let ix = textShadowIndex
        let r = ix.scalars(range) ?? (st.selection.lowerBound..<st.selection.lowerBound)
        let u = ix.nsRange(scalars: r.lowerBound, r.upperBound)
        actualRange?.pointee = u
        var rect = f.caret.cg
        rect.size.width = 0
        if let (origin, font) = fieldText(f) {
            let line = Self.line(st.text, font)
            let a = CTLineGetOffsetForStringIndex(line, u.location, nil)
            let b = CTLineGetOffsetForStringIndex(line, NSMaxRange(u), nil)
            rect.origin.x = origin.x + a
            rect.size.width = b - a
        }
        return screenRect(rect)
    }

    public func characterIndex(for point: NSPoint) -> Int {
        guard let f = shown?.frame.textInput, let st = textShadow.state, let window else { return NSNotFound }
        let p = convert(window.convertPoint(fromScreen: point), from: nil)
        guard f.rect.cg.contains(p), let (origin, font) = fieldText(f) else { return NSNotFound }
        let i = CTLineGetStringIndexForPosition(Self.line(st.text, font), CGPoint(x: p.x - origin.x, y: 0))
        return i == kCFNotFound ? NSNotFound : i
    }

    public func windowLevel() -> Int { window?.level.rawValue ?? 0 }

    public func baselineDeltaForCharacter(at anIndex: Int) -> CGFloat { 0 }

    private static func line(_ s: String, _ font: Font) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font.ctFont]))
    }

    /// Where and in which font the frame drew the field's text: the text draw whose string is
    /// the field's text and whose baseline starts inside the field. Positions within it come
    /// from Core Text with that font, the shaping the renderer uses.
    private func fieldText(_ f: TextInput) -> (CGPoint, Font)? {
        guard let frame = shown?.frame else { return nil }
        let box = f.rect.cg
        var fallback: (CGPoint, Font)?
        for case let .text(origin, font, _, s) in frame.draws {
            let o = CGPoint(x: CGFloat(origin.x), y: CGFloat(origin.y))
            guard box.contains(CGPoint(x: o.x + 0.5, y: o.y - 0.5)) else { continue }
            if s == f.text { return (o, font) }
            if fallback == nil { fallback = (o, font) }
        }
        if let fallback { return fallback }
        // An empty field may draw nothing (or a placeholder elsewhere): use the caret.
        if f.text.isEmpty { return (CGPoint(x: CGFloat(f.caret.x), y: 0), Font(family: 0, size: 13, weight: 400, italic: false)) }
        return nil
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
