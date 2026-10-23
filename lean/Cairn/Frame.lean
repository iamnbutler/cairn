module

public import Cairn.UI.Node
public import Cairn.Input

/-! What crosses the boundary each frame, before encoding. `Cairn.Frame.Encode` turns it into
bytes (see docs/frame.md). -/

@[expose] public section

namespace Cairn

inductive Draw where
  | rect (r : Rect) (fill : Option Color) (radius : Nat) (border : Option Border)
  /-- `origin` is the left end of the baseline. -/
  | text (origin : Point) (font : Font) (color : Color) (s : String)
  | pushClip (r : Rect)
  | popClip
deriving Repr, BEq, Inhabited

structure AxNode where
  control : Option ControlRef
  role : Role
  rect : Rect
  label : String
  value : String := ""
  /-- Index of the parent in the frame's `ax` array; roots have none. -/
  parent : Option Nat := none
  focused : Bool := false
  selected : Bool := false
  checked : Option Bool := none
deriving Repr, BEq, Inhabited

/-- Everything `NSTextInputClient` may ask about the focused field, answered without Lean. -/
structure TextInput where
  control : ControlRef
  rect : Rect
  caret : Rect
  text : String
  selection : Nat × Nat
  marked : Option (Nat × Nat)
  /-- The left end of the text's baseline, in window coordinates, after any horizontal
  scroll: where scalar 0 starts. -/
  textOrigin : Point := ⟨0, 0⟩
deriving Repr, BEq, Inhabited

structure Frame where
  size : Size
  draws : Array Draw
  ax : Array AxNode
  textInput : Option TextInput := none
  cursor : Cursor := .arrow
  effects : Array Effect := #[]
deriving Repr, Inhabited

end Cairn
