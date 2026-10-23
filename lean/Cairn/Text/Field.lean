import Cairn.Input
import Cairn.UI.Node

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

namespace Cairn.Text

/-! ## Characters -/

/-- Scalars that would start a new line. A single-line field never contains them: inserted and
pasted text has them removed (as HTML's `<input>` does). -/
def isLineBreak (c : Char) : Bool :=
  c == '\n' || c == '\r' || c == '\x0b' || c == '\x0c' || c == '\u0085' || c == ' ' ||
    c == ' '

/-- The text a field may contain: no line breaks. -/
def SingleLine (t : List Char) : Prop := ∀ c ∈ t, isLineBreak c = false

/-- `s` as scalars, with line breaks removed. -/
def clean (s : String) : List Char := s.toList.filter (fun c => !isLineBreak c)

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

/-- Delete `[a, b)` as its own undo step. -/
def deleteRange (f : Field) (a b : Nat) : Field :=
  f.edit (splice f.text a b []) a a true false

/-- Delete the selection if there is one, else `[a, b)`. -/
def deleteSelOr (f : Field) (a b : Nat) : Field :=
  if f.lo < f.hi then f.deleteRange f.lo f.hi else f.deleteRange a b

/-! ## Ops -/

/-- Typed or committed text replaces the marked text, else the selection. Consecutive typing at
a collapsed caret is one undo step; committing a composition joins the step its first
`setMarked` opened. -/
def insert (f : Field) (s : String) : Field :=
  let a := f.target.1
  let b := f.target.2
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
one step. An empty composition ends it. -/
def setMarked (f : Field) (s : String) (selStart selLen : Nat) : Field :=
  let a := f.target.1
  let b := f.target.2
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
  | .deleteBackward, f => (f.deleteSelOr (f.caret - 1) f.caret, [])
  | .deleteForward, f => (f.deleteSelOr f.caret (min (f.caret + 1) f.len), [])
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

/-! ## Tests -/

namespace Tests
open Field

private def st (f : Field) : String × Nat × Nat := (f.textString, f.caret, f.anchor)
private def run (s : String) (ops : List TextOp) : Field := (ofString s).applyAll ops
private def eff (f : Field) (op : TextOp) : List Effect := (apply op f).2

-- insert
#guard st (run "" [.insert "hi"]) == ("hi", 2, 2)
#guard st (run "ac" [.setCaret 1 false, .insert "b"]) == ("abc", 2, 2)
#guard st (run "hello" [.setCaret 1 false, .setCaret 4 true, .insert "ipp"]) == ("hippo", 4, 4)
#guard st (run "" [.insert "a\nb\r\nc"]) == ("abc", 3, 3)
#guard st (run "" [.insert "日本語"]) == ("日本語", 3, 3)
#guard st (run "ab" [.insert "😀"]) == ("ab😀", 3, 3)
-- deleteBackward / deleteForward
#guard st (run "abc" [.deleteBackward]) == ("ab", 2, 2)
#guard st (run "abc" [.moveHome false, .deleteBackward]) == ("abc", 0, 0)
#guard st (run "abc" [.selectAll, .deleteBackward]) == ("", 0, 0)
#guard st (run "abc" [.setCaret 1 false, .deleteForward]) == ("ac", 1, 1)
#guard st (run "abc" [.deleteForward]) == ("abc", 3, 3)
#guard st (run "abcd" [.setCaret 1 false, .setCaret 3 true, .deleteForward]) == ("ad", 1, 1)
-- word deletion
#guard st (run "hello big world" [.deleteWordBackward]) == ("hello big ", 10, 10)
#guard st (run "hello big world  " [.deleteWordBackward]) == ("hello big ", 10, 10)
#guard st (run "hello, world" [.moveHome false, .deleteWordForward]) == (", world", 0, 0)
#guard st (run "hello, world" [.setCaret 5 false, .deleteWordForward]) == ("hello", 5, 5)
#guard st (run "foo bar" [.setCaret 0 false, .setCaret 2 true, .deleteWordBackward]) == ("o bar", 0, 0)
-- character movement
#guard st (run "abc" [.moveLeft false]) == ("abc", 2, 2)
#guard st (run "abc" [.moveLeft true, .moveLeft true]) == ("abc", 1, 3)
#guard st (run "abc" [.moveLeft true, .moveLeft true, .moveLeft false]) == ("abc", 1, 1)
#guard st (run "abc" [.moveHome false, .moveLeft false]) == ("abc", 0, 0)
#guard st (run "abc" [.moveRight false]) == ("abc", 3, 3)
#guard st (run "abc" [.moveHome false, .moveRight true, .moveRight true]) == ("abc", 2, 0)
#guard st (run "abc" [.moveHome false, .moveRight true, .moveRight true, .moveRight false]) ==
  ("abc", 2, 2)
-- word movement
#guard st (run "one two  three" [.moveWordLeft false]) == ("one two  three", 9, 9)
#guard st (run "one two  three" [.moveWordLeft false, .moveWordLeft false]) ==
  ("one two  three", 4, 4)
#guard st (run "one two" [.moveHome false, .moveWordRight false]) == ("one two", 3, 3)
#guard st (run "one two" [.moveHome false, .moveWordRight true, .moveWordRight true]) ==
  ("one two", 7, 0)
#guard st (run "a.b" [.moveWordLeft false]) == ("a.b", 2, 2)
#guard st (run "café au lait" [.moveHome false, .moveWordRight false]) == ("café au lait", 4, 4)
#guard st (run "one two three" [.setCaret 4 false, .setCaret 7 true, .moveWordLeft false]) ==
  ("one two three", 0, 0)
-- line movement
#guard st (run "abc" [.moveHome false]) == ("abc", 0, 0)
#guard st (run "abc" [.moveHome true]) == ("abc", 0, 3)
#guard st (run "abc" [.moveHome false, .moveEnd true]) == ("abc", 3, 0)
-- setCaret, selectAll
#guard st (run "abc" [.setCaret 99 false]) == ("abc", 3, 3)
#guard st (run "abcd" [.setCaret 1 false, .setCaret 3 true]) == ("abcd", 3, 1)
#guard st (run "abc" [.selectAll]) == ("abc", 3, 0)
#guard (run "abc" [.setCaret 1 false, .setCaret 3 true]).selected == ['b', 'c']
-- cut, copy, paste
#guard eff (run "hello" [.setCaret 1 false, .setCaret 4 true]) .copy == [.setClipboard "ell"]
#guard eff (run "hello" []) .copy == []
#guard (apply .copy (run "hello" [.selectAll])).1 == run "hello" [.selectAll]
#guard eff (run "hello" [.setCaret 1 false, .setCaret 4 true]) .cut == [.setClipboard "ell"]
#guard st (run "hello" [.setCaret 1 false, .setCaret 4 true, .cut]) == ("ho", 1, 1)
#guard st (run "hello" [.cut]) == ("hello", 5, 5)
#guard st (run "hello" [.selectAll, .paste "bye\nnow"]) == ("byenow", 6, 6)
#guard st (run "ab" [.moveLeft false, .paste "XY"]) == ("aXYb", 3, 3)
-- undo / redo, with typing coalesced into one step
#guard st (run "" [.insert "a", .insert "b", .insert "c", .undo]) == ("", 0, 0)
#guard st (run "" [.insert "a", .insert "b", .undo, .redo]) == ("ab", 2, 2)
#guard st (run "" [.insert "ab", .moveLeft false, .insert "x", .undo]) == ("ab", 1, 1)
#guard st (run "" [.insert "ab", .moveLeft false, .insert "x", .undo, .undo]) == ("", 0, 0)
#guard st (run "abc" [.deleteBackward, .deleteBackward, .undo]) == ("ab", 2, 2)
#guard st (run "abc" [.selectAll, .insert "x", .insert "y", .undo]) == ("abc", 3, 0)
#guard st (run "hello" [.setCaret 1 false, .setCaret 4 true, .cut, .undo]) == ("hello", 4, 1)
#guard st (run "ab" [.paste "c", .paste "d", .undo]) == ("abc", 3, 3)
#guard st (run "a" [.insert "b", .undo, .insert "c", .redo]) == ("ac", 2, 2)
#guard eff (run "a" []) .undo == [.beep]
#guard eff (run "a" [.insert "b"]) .redo == [.beep]
#guard eff (run "a" [.insert "b"]) .undo == []
-- IME: k → か, then commit
#guard (run "" [.setMarked "k" 1 0]).marked == some (0, 1)
#guard st (run "" [.setMarked "k" 1 0]) == ("k", 1, 1)
#guard st (run "" [.setMarked "k" 1 0, .setMarked "か" 1 0]) == ("か", 1, 1)
#guard (run "" [.setMarked "k" 1 0, .setMarked "か" 1 0]).marked == some (0, 1)
#guard st (run "" [.setMarked "k" 1 0, .setMarked "か" 1 0, .unmark]) == ("か", 1, 1)
#guard (run "" [.setMarked "k" 1 0, .setMarked "か" 1 0, .unmark]).marked == none
-- composing inside existing text, with the IME's selection inside the marked text
#guard st (run "ab" [.moveLeft false, .setMarked "にほ" 0 2]) == ("aにほb", 3, 1)
#guard (run "ab" [.moveLeft false, .setMarked "にほ" 0 2]).marked == some (1, 3)
#guard st (run "ab" [.moveLeft false, .setMarked "にほ" 2 0, .insert "日本"]) == ("a日本b", 3, 3)
#guard (run "ab" [.moveLeft false, .setMarked "にほ" 2 0, .insert "日本"]).marked == none
-- composition replaces a selection; the whole composition is one undo step
#guard st (run "xyz" [.selectAll, .setMarked "k" 1 0, .setMarked "か" 1 0, .unmark]) ==
  ("か", 1, 1)
#guard st (run "xyz" [.selectAll, .setMarked "k" 1 0, .setMarked "か" 1 0, .unmark, .undo]) ==
  ("xyz", 3, 0)
#guard st (run "a" [.setMarked "k" 1 0, .setMarked "か" 1 0, .insert "か", .undo]) == ("a", 1, 1)
-- an empty composition ends it and restores the text before it
#guard st (run "a" [.setMarked "k" 1 0, .setMarked "" 0 0]) == ("a", 1, 1)
#guard (run "a" [.setMarked "k" 1 0, .setMarked "" 0 0]).marked == none
-- movement ends a composition, keeping its text
#guard st (run "a" [.setMarked "k" 1 0, .moveLeft false]) == ("ak", 1, 1)
#guard (run "a" [.setMarked "k" 1 0, .moveLeft false]).marked == none
-- view
#guard (run "hi" [.moveLeft true]).view true ==
  { text := "hi", caret := 1, anchor := 2, focused := true }
#guard (empty "What needs to be done?").view false ==
  { text := "", caret := 0, anchor := 0, placeholder := "What needs to be done?" }

end Tests
end Cairn.Text
