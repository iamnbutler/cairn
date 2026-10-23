module

public import Cairn.Geometry
public import Cairn.Claim
public import Cairn.Text.Metrics

/-! What `view` returns (`Node`) and what layout produces (`Laid`).

A `Node` says what is on screen and how it wants to be sized; layout turns it into a `Laid`
with every rect and clip resolved. A node that performs a move carries a `Control` naming the
claim, which is how presence, pressability and the accessibility mirror find it. -/

@[expose] public section


namespace Cairn

structure Color where
  r : UInt8
  g : UInt8
  b : UInt8
  a : UInt8 := 255
deriving Repr, BEq, DecidableEq, Inhabited

/-- `row` and `column` lay children out along an axis; `stack` puts them on top of each other,
later children on top. -/
inductive Axis where
  | row | column | stack
deriving Repr, BEq, DecidableEq, Inhabited

inductive Align where
  | start | center | finish | stretch
deriving Repr, BEq, DecidableEq, Inhabited

/-- `fill` shares the parent's leftover main-axis space equally among `fill` children, and
takes the parent's full cross-axis size. -/
inductive Sizing where
  | fixed (n : Nat) | hug | fill
deriving Repr, BEq, DecidableEq, Inhabited

structure Border where
  width : Nat
  color : Color
deriving Repr, BEq, DecidableEq, Inhabited

structure Style where
  axis : Axis := .column
  width : Sizing := .hug
  height : Sizing := .hug
  padding : Insets := {}
  gap : Nat := 0
  /-- Cross-axis alignment of children. -/
  align : Align := .start
  /-- Main-axis placement of children when there's space left over. -/
  justify : Align := .start
  background : Option Color := none
  border : Option Border := none
  radius : Nat := 0
  /-- Clip children to this box. -/
  clip : Bool := false
deriving Repr, BEq, Inhabited

inductive Role where
  | group | button | checkbox | text | textField | link | list | listItem | heading | tab
deriving Repr, BEq, DecidableEq, Inhabited

/-- A node that performs a move. -/
structure Control where
  ref : ControlRef
  role : Role := .button
  label : String
  value : String := ""
  checked : Option Bool := none
  selected : Bool := false
deriving Repr, BEq, Inhabited

structure TextStyle where
  font : Font := {}
  color : Color := ⟨0, 0, 0, 255⟩
deriving Repr, BEq, Inhabited

/-- What a text field shows. Indices are Unicode scalar positions into `text`. The editing
model that produces this lives in `Cairn.Text`. -/
structure FieldView where
  text : String
  caret : Nat
  /-- Selection is `[min anchor caret, max anchor caret)`. -/
  anchor : Nat
  /-- IME composition in progress, as a range of `text`. -/
  marked : Option (Nat × Nat) := none
  placeholder : String := ""
  focused : Bool := false
deriving Repr, BEq, Inhabited

/-- Which lines a wrapped text keeps when it has more than `maxLines`: the first ones, or the
last ones (a growing transcript that shows its end). -/
inductive Keep where
  | head | tail
deriving Repr, BEq, DecidableEq, Inhabited

/-- How a wrapped text (`Node.para`) is sized and broken into lines. The rules are in
`docs/layout.md` ("Wrapped text") and `Cairn.Text.Wrap`. -/
structure Wrap where
  /-- `fixed n` wraps at `n`; `hug` and `fill` wrap at the width the parent offers. `fill` then
  takes the parent's whole cross or leftover length; `hug` the widest line. -/
  width : Sizing := .fill
  /-- `hug` is the lines' height (lines × line height). A shorter `fixed` height clips. -/
  height : Sizing := .hug
  /-- Keep at most this many lines. -/
  maxLines : Option Nat := none
  keep : Keep := .head
  /-- Where each line sits in the width: `start` (and `stretch`) left, `center`, `finish` right. -/
  align : Align := .start
deriving Repr, BEq, Inhabited

inductive Node where
  | box (style : Style) (control : Option Control) (children : List Node)
  | text (style : TextStyle) (content : String)
  /-- Text wrapped at word boundaries to the available width (`Cairn.Text.Wrap`). Layout turns
  it into a clipping column of one `text` per line, so it has no `Laid` form of its own. -/
  | para (style : TextStyle) (wrap : Wrap) (content : String)
  | field (style : Style) (text : TextStyle) (control : Control) (view : FieldView)
deriving Repr, Inhabited

/-- A laid-out node. `clip` is the region this node may paint in (the intersection of every
clipping ancestor), so the visible part of a node is `rect.inter clip`. -/
inductive Laid where
  | box (rect clip : Rect) (style : Style) (control : Option Control) (children : List Laid)
  | text (rect clip : Rect) (baseline : Int) (style : TextStyle) (content : String)
  | field (rect clip : Rect) (style : Style) (text : TextStyle) (control : Control)
      (view : FieldView) (textOrigin : Point) (caret : Rect) (selection : List Rect)
deriving Repr, Inhabited

namespace Laid

def rect : Laid → Rect
  | .box r .. | .text r .. | .field r .. => r

def clip : Laid → Rect
  | .box _ c .. | .text _ c .. | .field _ c .. => c

def visible (l : Laid) : Rect := l.rect.inter l.clip

def control? : Laid → Option Control
  | .box _ _ _ c _ => c
  | .field _ _ _ _ c .. => some c
  | .text .. => none

end Laid
end Cairn
