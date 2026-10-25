import CairnFrame
import Foundation

/// The focused field as the input system sees it: text, selection and marked range, in Unicode
/// scalar indices (Lean's), `[lo, hi)`.
public struct FieldState: Equatable, Sendable, CustomStringConvertible {
    public var control: ControlRef
    public var text: String
    public var selection: Range<Int>
    public var marked: Range<Int>?
    /// A secure field: its text is one bullet per scalar, here as in Lean's frame.
    public var secure: Bool

    public init(control: ControlRef, text: String, selection: Range<Int>, marked: Range<Int>?,
                secure: Bool = false) {
        self.control = control
        self.text = text
        self.selection = selection
        self.marked = marked
        self.secure = secure
    }

    public init(_ t: TextInput) {
        let n = t.text.unicodeScalars.count
        func clamp(_ a: UInt32, _ b: UInt32) -> Range<Int> {
            let lo = min(Int(min(a, b)), n), hi = min(Int(max(a, b)), n)
            return lo..<hi
        }
        self.init(control: t.control, text: t.text, selection: clamp(t.selection.start, t.selection.end),
                  marked: t.marked.flatMap { $0.start == $0.end ? nil : clamp($0.start, $0.end) },
                  secure: t.secure)
    }

    public var description: String {
        "\(control.label) \"\(text)\" sel \(selection.lowerBound)..<\(selection.upperBound)"
            + (marked.map { " marked \($0.lowerBound)..<\($0.upperBound)" } ?? "")
    }

    /// Lean's `Cairn.Text.isLineBreak`: a single-line field stores each of these as a space
    /// (`Field.clean`), so inserted and marked text is flattened the same way here.
    static func flatten(_ u: Unicode.Scalar) -> Unicode.Scalar {
        switch u.value {
        case 0x0A, 0x0D, 0x0B, 0x0C, 0x85, 0x2028, 0x2029: return " "
        default: return u
        }
    }

    /// What a secure field shows for each scalar (Lean's `Cairn.Text.bullet`).
    static let bullet: Unicode.Scalar = "\u{2022}"

    /// Replaces scalar range `r` (clamped) with `s`, line breaks flattened (each scalar a bullet
    /// in a secure field, which is all its frame shows); returns where `s` starts.
    fileprivate mutating func replace(_ r: Range<Int>, with s: String) -> Int {
        var scalars = Array(text.unicodeScalars)
        let lo = min(r.lowerBound, scalars.count), hi = min(max(r.upperBound, lo), scalars.count)
        scalars.replaceSubrange(lo..<hi, with: s.unicodeScalars.map { secure ? Self.bullet : Self.flatten($0) })
        var u = String.UnicodeScalarView()
        u.append(contentsOf: scalars)
        text = String(u)
        return lo
    }
}

/// A frame's text state that the shadow predicted differently. The conformance driver reads
/// these (`HostView.shadowDivergences`); each one means the host's model of `Field.apply`
/// (below) and Lean's disagree for some edit.
public struct ShadowDivergence: Sendable, CustomStringConvertible {
    public var throughSeq: UInt64
    public var expected: FieldState?
    public var actual: FieldState?
    public var description: String {
        "through #\(throughSeq): expected \(expected.map(\.description) ?? "no field"), Lean has \(actual.map(\.description) ?? "no field")"
    }
}

/// The host's local copy of the focused field, for answering `NSTextInputClient`.
///
/// The input system queries the client synchronously, straight after it calls `setMarkedText` or
/// `insertText`, and the main thread may not wait for Lean. So the shadow applies each text edit
/// itself, optimistically, the way Lean will (Chromium does the same in its browser process):
///
/// - the replaced range is the explicit replacement range, else the marked text, else the
///   selection;
/// - line breaks in the new text become spaces (the field is single-line);
/// - `setMarked(s, sel)` puts `s` there, marks it (nothing if `s` is empty) and selects `sel`
///   inside it;
/// - `insertText(s)` puts `s` there, unmarks, and leaves the caret after it;
/// - `unmark` keeps the text and selection and drops the mark.
///
/// When a frame arrives that includes every edit the shadow applied, the shadow is replaced by
/// Lean's state. If no other edit-capable event (a key, a click, an Edit-menu command) was sent
/// in between, the two must agree; when they don't, that is a divergence, recorded for the
/// conformance driver. Listed in docs/trusted.md.
public struct TextInputShadow: Sendable {
    public private(set) var state: FieldState?
    /// The last event this shadow accounts for.
    public private(set) var seq: UInt64 = 0
    /// Text edits applied locally since the last frame was adopted.
    public private(set) var predicted = false
    /// Another event that may change the field was sent since the last adopted frame, so the
    /// prediction can't be checked.
    public private(set) var tainted = false
    /// How many predictions were checked against Lean's frame (for a divergence rate).
    public private(set) var checks = 0

    public init() {}

    /// The outcome of a frame arriving.
    public enum Reconcile: Sendable {
        /// The frame doesn't include all local edits yet; the shadow stands.
        case pending
        /// The frame was adopted. `external`: it changed the field in a way the shadow didn't
        /// predict (Lean moved the caret, changed the text, or ended the composition on its own).
        case adopted(external: Bool, previous: FieldState?)
        /// The frame was adopted, and it contradicts an untainted prediction.
        case diverged(ShadowDivergence)
    }

    public mutating func frameArrived(_ t: TextInput?, throughSeq: UInt64) -> Reconcile {
        guard throughSeq >= seq else { return .pending }
        let actual = t.map(FieldState.init)
        let previous = state
        let checked = predicted && !tainted
        state = actual
        seq = throughSeq
        defer { predicted = false; tainted = false }
        if checked { checks += 1 }
        if checked && previous != actual {
            return .diverged(ShadowDivergence(throughSeq: throughSeq, expected: previous, actual: actual))
        }
        return .adopted(external: !checked && previous != actual, previous: previous)
    }

    /// An event that may change the field but that the shadow doesn't model.
    public mutating func taint(seq s: UInt64) {
        tainted = true
        seq = max(seq, s)
    }

    private mutating func target(_ replace: Range<Int>?) -> Range<Int>? {
        guard let st = state else { return nil }
        return replace ?? st.marked ?? st.selection
    }

    public mutating func setMarked(_ s: String, selection sel: Range<Int>, replacing: Range<Int>?, seq s2: UInt64) {
        seq = max(seq, s2)
        predicted = true
        guard let r = target(replacing), var st = state else { return }
        let lo = st.replace(r, with: s)
        let n = s.unicodeScalars.count
        st.marked = n == 0 ? nil : lo..<(lo + n)
        let a = min(sel.lowerBound, n), b = min(max(sel.upperBound, a), n)
        st.selection = (lo + a)..<(lo + b)
        state = st
    }

    public mutating func insert(_ s: String, replacing: Range<Int>?, seq s2: UInt64) {
        seq = max(seq, s2)
        predicted = true
        guard let r = target(replacing), var st = state else { return }
        let lo = st.replace(r, with: s)
        let end = lo + s.unicodeScalars.count
        st.marked = nil
        st.selection = end..<end
        state = st
    }

    public mutating func unmark(seq s2: UInt64) {
        seq = max(seq, s2)
        predicted = true
        state?.marked = nil
    }
}
