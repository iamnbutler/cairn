module

public import Cairn.Input
public import Cairn.UI.Node

/-! # Single-line text editing

`Field` is the editing model behind every text field: the text, caret, anchor, IME marked range,
undo and redo stacks, and placeholder. `Field.apply` gives the meaning of every `TextOp`;
`Field.view` turns a field into the `FieldView` the view layer draws.

The text is a `List Char`, so every index is a Unicode scalar position, the same unit as
`String.length` and `TextMetrics.offsets`. Lists are used rather than `String` because every
edit is a splice (`take a ++ s ++ drop b`), and core Lean's `List` lemmas about `take`, `drop`
and `length` make the proofs short; `String`'s byte-indexed API would put a UTF-8 decoding step
between every theorem and its statement. The view converts with `String.ofList`
(`String.length_ofList` keeps the indices meaning the same thing).

The behaviour is specified, op by op and against macOS's `NSTextView`, in `docs/text.md`.
Theorems are in `Cairn.Text.Proofs`. -/

@[expose] public section

namespace Cairn.Text

/-! ## Characters -/

/-- Scalars that would start a new line. A single-line field never contains them: inserted and
pasted text has each one replaced by a space, as `NSTextField` does in single-line mode. -/
def isLineBreak (c : Char) : Bool :=
  c == '\n' || c == '\r' || c == '\x0b' || c == '\x0c' || c == '\u0085' || c == ' ' ||
    c == ' '

/-- The text a field may contain: no line breaks. -/
def SingleLine (t : List Char) : Prop := ∀ c ∈ t, isLineBreak c = false

/-- One scalar as a single-line field stores it: a line break becomes a space. -/
def flatten (c : Char) : Char := if isLineBreak c then ' ' else c

/-- `s` as scalars, each line break replaced by a space. Same length as `s`. -/
def clean (s : String) : List Char := s.toList.map flatten

/-- A word is a maximal run of word characters: ASCII letters, digits and `_`, and every non-ASCII
scalar except the Unicode spaces below. Everything else (ASCII punctuation and spaces) separates
words. This is deliberately simpler than `NSTextView`, which uses ICU word boundaries and a
dictionary for scripts without spaces; see `docs/text.md`. -/
def isWordChar (c : Char) : Bool :=
  c.isAlphanum || c == '_' ||
    (c.val ≥ 128 && !(c == ' ' || c == ' ' || (c.val ≥ 0x2000 && c.val ≤ 0x200a) ||
      c == ' ' || c == ' ' || c == '　'))

/-- The length of the longest prefix of `l` whose scalars satisfy `p`. -/
def span (p : Char → Bool) : List Char → Nat
  | [] => 0
  | c :: cs => if p c then span p cs + 1 else 0

/-- Where Option-Left goes from `i`: back over separators, then back over a word. -/
def wordLeft (t : List Char) (i : Nat) : Nat :=
  let pre := (t.take i).reverse
  let a := span (fun c => !isWordChar c) pre
  let b := span isWordChar (pre.drop a)
  i - (a + b)

/-- Where Option-Right goes from `i`: forward over separators, then forward over a word. -/
def wordRight (t : List Char) (i : Nat) : Nat :=
  let rest := t.drop i
  let a := span (fun c => !isWordChar c) rest
  let b := span isWordChar (rest.drop a)
  i + (a + b)

/-- `t` with `[a, b)` replaced by `s`. -/
def splice (t : List Char) (a b : Nat) (s : List Char) : List Char :=
  t.take a ++ s ++ t.drop b

/-! ## State -/

/-- What an undo step restores: the text and the selection. -/
structure Snapshot where
  text : List Char
  caret : Nat
  anchor : Nat
deriving Repr, BEq, DecidableEq, Inhabited

structure Field where
  /-- Unicode scalars; never contains a line break (`SingleLine`). -/
  text : List Char := []
  /-- Where the insertion point is, and the end of the selection that moves. -/
  caret : Nat := 0
  /-- The fixed end of the selection. The selection is `[min caret anchor, max caret anchor)`. -/
  anchor : Nat := 0
  /-- IME composition in progress, `[start, end)` of `text`. -/
  marked : Option (Nat × Nat) := none
  /-- Most recent first. Each entry is the state before an undoable edit. -/
  undoStack : List Snapshot := []
  /-- Most recent first. Cleared by every edit that changes the text. -/
  redoStack : List Snapshot := []
  /-- The last op was a typing insert; another one at a collapsed caret joins its undo step. -/
  typing : Bool := false
  placeholder : String := ""
deriving Repr, BEq, DecidableEq, Inhabited

namespace Field

/-- An empty field. -/
def empty (placeholder : String := "") : Field := { placeholder }

/-- A field holding `s` (line breaks removed) with the caret at the end. -/
def ofString (s : String) (placeholder : String := "") : Field :=
  let t := clean s
  { text := t, caret := t.length, anchor := t.length, placeholder }

def lo (f : Field) : Nat := min f.caret f.anchor
def hi (f : Field) : Nat := max f.caret f.anchor
def len (f : Field) : Nat := f.text.length

/-- The selected scalars, `[lo, hi)`. -/
def selected (f : Field) : List Char := (f.text.drop f.lo).take (f.hi - f.lo)

def snapshot (f : Field) : Snapshot := ⟨f.text, f.caret, f.anchor⟩

def textString (f : Field) : String := String.ofList f.text

/-- The range an insertion or composition replaces: the marked text if there is any, else the
selection. -/
def target (f : Field) : Nat × Nat := f.marked.getD (f.lo, f.hi)

/-- The range an input-method edit replaces: the explicit `replace` range when the input system
gives one (press-and-hold accents, reconversion, Korean IMEs that rewrite the last syllable),
clamped into the text, else `target`. -/
def targetOr (f : Field) : Option (Nat × Nat) → Nat × Nat
  | none => f.target
  | some (a, b) => (min a (min b f.len), min b f.len)

/-! ## Primitive transitions -/

/-- Set the text and selection after an edit. When the text really changes, the old state is
pushed for undo (if `push`) and redo is cleared; when it doesn't, only the selection moves and
nothing is recorded. -/
def edit (f : Field) (text : List Char) (caret anchor : Nat) (push typing : Bool) : Field :=
  if text = f.text then
    { f with caret, anchor, marked := none, typing := false }
  else
    { f with text, caret, anchor, marked := none, typing,
             undoStack := if push then f.snapshot :: f.undoStack else f.undoStack,
             redoStack := [] }

/-- Move the caret to `i`, keeping the anchor when extending. Ends any composition. -/
def moveTo (f : Field) (i : Nat) (extend : Bool) : Field :=
  { f with caret := i, anchor := if extend then f.anchor else i, marked := none, typing := false }

/-- Delete `[a, b)`. With `coalesce`, the deletion joins an open typing step and keeps it open
(Backspace while typing); otherwise it is its own undo step. -/
def deleteRange (f : Field) (a b : Nat) (coalesce : Bool := false) : Field :=
  f.edit (splice f.text a b []) a a (!(coalesce && f.typing)) coalesce

/-- Delete the selection if there is one (its own undo step), else `[a, b)`. -/
def deleteSelOr (f : Field) (a b : Nat) (coalesce : Bool := false) : Field :=
  if f.lo < f.hi then f.deleteRange f.lo f.hi else f.deleteRange a b coalesce

/-! ## Ops -/

/-- Typed or committed text replaces the marked text, else the selection. Consecutive typing at
a collapsed caret is one undo step; committing a composition joins the step its first
`setMarked` opened. `replace` is the input system's replacement range (see `targetOr`). -/
def insert (f : Field) (s : String) (replace : Option (Nat × Nat) := none) : Field :=
  let a := (f.targetOr replace).1
  let b := (f.targetOr replace).2
  let cs := clean s
  let push := f.marked.isNone && !(f.typing && f.lo == f.hi)
  f.edit (splice f.text a b cs) (a + cs.length) (a + cs.length) push true

/-- Like `insert`, but always its own undo step (unless it commits a composition). -/
def paste (f : Field) (s : String) : Field :=
  let a := f.target.1
  let b := f.target.2
  let cs := clean s
  f.edit (splice f.text a b cs) (a + cs.length) (a + cs.length) f.marked.isNone false

/-- IME composition: replace the marked text (or, when composition starts, the selection) with
`s`, mark it, and put the selection at `[selStart, selStart + selLen)` within it, clamped.
Starting a composition opens an undo step; the whole composition, through its commit, is that
one step. An empty composition ends it. `replace` is as for `insert`. -/
def setMarked (f : Field) (s : String) (selStart selLen : Nat)
    (replace : Option (Nat × Nat) := none) : Field :=
  let a := (f.targetOr replace).1
  let b := (f.targetOr replace).2
  let cs := clean s
  let n := cs.length
  let text := splice f.text a b cs
  let marked : Option (Nat × Nat) := if n = 0 then none else some (a, a + n)
  let changed := decide (text ≠ f.text)
  let push := f.marked.isNone && (changed || marked.isSome)
  { f with text, marked,
           caret := a + min (selStart + selLen) n, anchor := a + min selStart n,
           typing := false,
           undoStack := if push then f.snapshot :: f.undoStack else f.undoStack,
           redoStack := if push || changed then [] else f.redoStack }

/-- Commit the composition as it stands; the text and selection stay. -/
def unmark (f : Field) : Field := { f with marked := none, typing := false }

def undo (f : Field) : Field × List Effect :=
  match f.undoStack with
  | [] => (f, [.beep])
  | s :: rest =>
    ({ f with text := s.text, caret := s.caret, anchor := s.anchor, marked := none,
              typing := false, undoStack := rest, redoStack := f.snapshot :: f.redoStack }, [])

def redo (f : Field) : Field × List Effect :=
  match f.redoStack with
  | [] => (f, [.beep])
  | s :: rest =>
    ({ f with text := s.text, caret := s.caret, anchor := s.anchor, marked := none,
              typing := false, redoStack := rest, undoStack := f.snapshot :: f.undoStack }, [])

def clipboard (f : Field) : List Effect :=
  if f.lo < f.hi then [.setClipboard (String.ofList f.selected)] else []

/-- The meaning of every `TextOp`. See `docs/text.md`. -/
def apply : TextOp → Field → Field × List Effect
  | .insert s, f => (f.insert s, [])
  | .deleteBackward, f => (f.deleteSelOr (f.caret - 1) f.caret true, [])
  | .deleteForward, f => (f.deleteSelOr f.caret (min (f.caret + 1) f.len) true, [])
  | .deleteWordBackward, f => (f.deleteSelOr (wordLeft f.text f.caret) f.caret, [])
  | .deleteWordForward, f => (f.deleteSelOr f.caret (min (wordRight f.text f.caret) f.len), [])
  | .moveLeft ext, f =>
    (if !ext && f.lo < f.hi then f.moveTo f.lo false else f.moveTo (f.caret - 1) ext, [])
  | .moveRight ext, f =>
    (if !ext && f.lo < f.hi then f.moveTo f.hi false
     else f.moveTo (min (f.caret + 1) f.len) ext, [])
  | .moveWordLeft ext, f =>
    (f.moveTo (wordLeft f.text (if ext then f.caret else f.lo)) ext, [])
  | .moveWordRight ext, f =>
    (f.moveTo (min (wordRight f.text (if ext then f.caret else f.hi)) f.len) ext, [])
  | .moveHome ext, f => (f.moveTo 0 ext, [])
  | .moveEnd ext, f => (f.moveTo f.len ext, [])
  | .setCaret i ext, f => (f.moveTo (min i f.len) ext, [])
  | .selectAll, f => ({ f with anchor := 0, caret := f.len, marked := none, typing := false }, [])
  | .setMarked s i n, f => (f.setMarked s i n, [])
  | .unmark, f => (f.unmark, [])
  | .cut, f => (if f.lo < f.hi then f.deleteRange f.lo f.hi else f, f.clipboard)
  | .copy, f => (f, f.clipboard)
  | .paste s, f => (f.paste s, [])
  | .undo, f => f.undo
  | .redo, f => f.redo

/-- Apply ops in order, dropping effects. -/
def applyAll (f : Field) (ops : List TextOp) : Field :=
  ops.foldl (fun g op => (apply op g).1) f

/-- Apply `op` `n` times. -/
def iterate (op : TextOp) : Nat → Field → Field
  | 0, f => f
  | n + 1, f => (apply op (iterate op n f)).1

/-- What the view layer draws. -/
def view (f : Field) (focused : Bool) : FieldView :=
  { text := f.textString, caret := f.caret, anchor := f.anchor, marked := f.marked,
    placeholder := f.placeholder, focused }

/-! ## Well-formedness -/

def _root_.Cairn.Text.Snapshot.WF (s : Snapshot) : Prop :=
  s.caret ≤ s.text.length ∧ s.anchor ≤ s.text.length ∧ SingleLine s.text

/-- Every index is a position in the text, and the text is a single line. -/
structure WF (f : Field) : Prop where
  caret_le : f.caret ≤ f.text.length
  anchor_le : f.anchor ≤ f.text.length
  marked_le : ∀ a b, f.marked = some (a, b) → a ≤ b ∧ b ≤ f.text.length
  single : SingleLine f.text
  undo_wf : ∀ s ∈ f.undoStack, s.WF
  redo_wf : ∀ s ∈ f.redoStack, s.WF

end Field

/-! ## Secure fields

A secure field is a password field, as `NSSecureTextField`: the same editing model, but it
draws a bullet per scalar, refuses copy and cut with a beep, and keeps no undo history. It wraps
a `Field` rather than flagging one, so `Field.apply` and every theorem and claim stated with it
mean what they did. The typed text is in Lean (typed text always is) but never in its view:
`view` puts bullets in `FieldView.text`, so what layout measures, the frame draws and every dump
prints is its length only (`SecureField.view_agree`, `Dump.secure_frame`). Theorems are in
`Cairn.Text.Proofs`; the rules are in `docs/text.md`, "Secure fields". -/

/-- What a secure field draws for each scalar. -/
def bullet : Char := '•'

/-- `n` bullets. -/
def bullets (n : Nat) : String := String.ofList (List.replicate n bullet)

/-- A password field: a `Field` whose history is always empty. -/
structure SecureField where
  field : Field := {}
deriving Repr, BEq, DecidableEq, Inhabited

namespace SecureField

/-- An empty secure field. -/
def empty (placeholder : String := "") : SecureField := ⟨Field.empty placeholder⟩

/-- What was typed. Only for the one request that sends it (with `redact := true`). -/
def text (f : SecureField) : String := f.field.textString

def len (f : SecureField) : Nat := f.field.text.length

/-- The field without undo or redo history. -/
def forget (f : Field) : Field := { f with undoStack := [], redoStack := [] }

/-- Like `Field.apply`, except that copy, cut, undo and redo beep and change nothing, and no
history is kept. -/
def apply : TextOp → SecureField → SecureField × List Effect
  | .copy, f | .cut, f | .undo, f | .redo, f => (⟨forget f.field⟩, [.beep])
  | op, f => (⟨forget (Field.apply op f.field).1⟩, (Field.apply op f.field).2)

/-- Apply ops in order, dropping effects. -/
def applyAll (f : SecureField) (ops : List TextOp) : SecureField :=
  ops.foldl (fun g op => (apply op g).1) f

/-- What the view layer draws: a bullet per scalar, the field's selection and composition, and
`secure`. -/
def view (f : SecureField) (focused : Bool) : FieldView :=
  { text := bullets f.field.text.length, caret := f.field.caret, anchor := f.field.anchor,
    marked := f.field.marked, placeholder := f.field.placeholder, focused, secure := true }

/-- Two secure fields that show the same: the same number of scalars, selection, composition
and placeholder, whatever the scalars are. -/
def Agree (f g : SecureField) : Prop :=
  f.field.text.length = g.field.text.length ∧ f.field.caret = g.field.caret ∧
    f.field.anchor = g.field.anchor ∧ f.field.marked = g.field.marked ∧
    f.field.placeholder = g.field.placeholder

/-- **Bullets**: the view's text is one bullet per scalar typed. -/
theorem view_text (f : SecureField) (b : Bool) :
    (f.view b).text.toList = List.replicate f.field.text.length bullet ∧ (f.view b).secure = true := by
  simp only [view, bullets, String.toList_ofList, and_self]

/-- **The view hides the text**: two secure fields that agree on everything but which scalars
were typed have the same view, so nothing built from it (layout, the frame, the accessibility
mirror, a dump) can tell them apart. -/
theorem view_agree {f g : SecureField} (h : f.Agree g) (b : Bool) : f.view b = g.view b := by
  obtain ⟨h1, h2, h3, h4, h5⟩ := h
  simp only [view, h1, h2, h3, h4, h5]

end SecureField

end Cairn.Text
