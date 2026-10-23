module

public import Cairn.Geometry
public import Cairn.Claim

/-! What the host sends Lean (`Event`), what the runtime gives an app (`Action`), and what an
app asks the host to do (`Effect`). -/

@[expose] public section


namespace Cairn

structure Mods where
  shift : Bool := false
  command : Bool := false
  option : Bool := false
  control : Bool := false
deriving Repr, BEq, DecidableEq, Inhabited

inductive Button where
  | primary | secondary
deriving Repr, BEq, DecidableEq, Inhabited

/-- Keys the host reports by meaning. Printable text arrives as `insertText`, not as keys;
`char` is only for shortcuts with a modifier. -/
inductive Key where
  | enter | escape | tab | backspace | delete
  | left | right | up | down | home | finish | pageUp | pageDown
  | char (c : Char)
deriving Repr, BEq, DecidableEq, Inhabited

/-- Host → Lean. Points are logical, in the window's content area. -/
inductive Event where
  | pointerMove (p : Point)
  | pointerDown (p : Point) (button : Button) (clicks : Nat) (mods : Mods)
  | pointerUp (p : Point) (button : Button) (mods : Mods)
  | pointerExit
  | scroll (p : Point) (dx dy : Int)
  | key (k : Key) (mods : Mods)
  /-- Committed text from the input system (typing, IME commit, dictation). With `replace`,
  the text replaces that range `[a, b)` of the focused field (scalar indices) instead of the
  selection. -/
  | insertText (s : String) (replace : Option (Nat × Nat) := none)
  /-- IME composition: the marked text and the selection within it, optionally replacing the
  range `replace` of the focused field. -/
  | setMarked (s : String) (selStart selLen : Nat) (replace : Option (Nat × Nat) := none)
  | unmark
  | copy | cut | selectAll | undo | redo
  | paste (s : String)
  | resize (size : Size)
  /-- Backing scale × 100 (200 on a Retina display). -/
  | scale (percent : Nat)
  | windowFocus (focused : Bool)
deriving Repr, BEq, Inhabited

/-- Edits to a text field's model. The runtime turns key and text events into these; the
semantics are `Cairn.Text.Field.apply`. -/
inductive TextOp where
  | insert (s : String)
  | deleteBackward | deleteForward | deleteWordBackward | deleteWordForward
  | moveLeft (extend : Bool) | moveRight (extend : Bool)
  | moveWordLeft (extend : Bool) | moveWordRight (extend : Bool)
  | moveHome (extend : Bool) | moveEnd (extend : Bool)
  | setCaret (i : Nat) (extend : Bool)
  | selectAll
  | setMarked (s : String) (selStart selLen : Nat)
  | unmark
  | cut | copy | paste (s : String)
  | undo | redo
deriving Repr, BEq, Inhabited

/-- Runtime → app. Every action names the control it came from, so every behaviour can be
traced to a claim. -/
inductive Action where
  | press (c : ControlRef)
  | doublePress (c : ControlRef)
  | edit (c : ControlRef) (op : TextOp)
  | submit (c : ControlRef)
  | cancel (c : ControlRef)
  | blur (c : ControlRef)
deriving Repr, BEq, Inhabited

def Action.control : Action → ControlRef
  | .press c | .doublePress c | .edit c _ | .submit c | .cancel c | .blur c => c

inductive Cursor where
  | arrow | pointer | text
deriving Repr, BEq, DecidableEq, Inhabited

/-- App → host (and runtime). -/
inductive Effect where
  | setClipboard (s : String)
  | beep
  /-- Move keyboard focus to the control `c`. The runtime runs this one, not the host: after the
  step's actions it sets `ui.focus := some c`, and keeps it only if `c` is a focusable control
  of the new tree (docs/runtime.md). No `blur` is delivered for a field it takes focus from.
  The host decodes it and does nothing. -/
  | focus (c : ControlRef)
deriving Repr, BEq, Inhabited

end Cairn
