module

public import Cairn.Geometry
public import Cairn.Claim
public import Cairn.Font
public import Cairn.Effects

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

-- region: node-sizing
/-- `fill` shares the parent's leftover main-axis space equally among `fill` children, and
takes the parent's full cross-axis size. -/
inductive Sizing where
  | fixed (n : Nat) | hug | fill
deriving Repr, BEq, DecidableEq, Inhabited
-- endregion: node-sizing

structure Border where
  width : Nat
  color : Color
deriving Repr, BEq, DecidableEq, Inhabited

/-- How a rounded box's corners turn: a circular arc, or Apple's continuous curve (SwiftUI's
`RoundedRectangle(style: .continuous)`), which starts further along the edge and has no jump in
curvature. -/
inductive Corner where
  | circular | continuous
deriving Repr, BEq, DecidableEq, Inhabited

/-- A soft shadow under a box's shape, as SwiftUI's `shadow(color:radius:x:y:)`: the shape's
silhouette in `color`, blurred by `radius` points and moved by `(x, y)`. With no offset it is a
glow. -/
structure Shadow where
  color : Color
  radius : Nat
  x : Int := 0
  y : Int := 0
deriving Repr, BEq, DecidableEq, Inhabited

/-- Pixels the host draws: the shader registered under `shader` fills the box, fed with these
numbers (what they mean is the shader's contract) and with the host's clock, as milliseconds
since `origin` (a time on the runtime's monotonic clock), so it can move between frames. -/
structure Paint where
  shader : String
  origin : Nat := 0
  scalars : List Int := []
  arrays : List (List Int) := []
deriving Repr, BEq, DecidableEq, Inhabited

/-- How an image's pixels fill its box: stretched to it (`fill`), scaled to fit inside it with the
aspect ratio kept (`contain`, centred, leaving bands), or scaled to cover it with the aspect ratio
kept (`cover`, centred, cut by the box). -/
inductive Fit where
  | fill | contain | cover
deriving Repr, BEq, DecidableEq, Inhabited

/-- Host-drawn pixels from a loaded image: the host paints the image it holds for `source` into
the box as `fit` says. `width` and `height` are its size in pixels, as the load answered
(`Reply.image`); Lean places it from them (`Frame.imageDest`), so the host only scales. -/
structure ImageFill where
  source : String
  width : Nat
  height : Nat
  fit : Fit := .cover
deriving Repr, BEq, DecidableEq, Inhabited

/-! ### Virtual lists: what the runtime knows of one

The data a virtual list (`Cairn.UI.VList`, docs/layout.md, "Virtual lists") and the runtime pass
each other. The logic is in `Cairn.UI.VList`. -/

namespace VList

/-- A row whose height is known: it was laid at that height. -/
structure Row where
  /-- Its place in the list's keys. -/
  index : Nat
  key : Nat
  /-- Its height as laid, at least one point. -/
  height : Nat
deriving Repr, BEq, DecidableEq, Inhabited

/-- The row the reader is at: the first row showing at the offset `offset`, whose top in the
list's content was `top` in the heights it was recorded with. -/
structure Anchor where
  key : Nat
  top : Int
  offset : Int
deriving Repr, BEq, DecidableEq, Inhabited

/-- What the runtime knows of one list (`UI.lists`), recorded after every layout: the heights of
the rows it has laid, sorted by index, at the width they were laid at; the box's length; and
the anchor. -/
structure Known where
  /-- The width the rows were laid at: a different width forgets every height. -/
  width : Int := 0
  /-- The number of rows when they were recorded. -/
  count : Nat := 0
  rows : Array Row := #[]
  /-- The box's length the last time it was laid; 0 before then. -/
  viewport : Int := 0
  anchor : Option Anchor := none
  /-- The estimate for the rows not yet laid: the mean of the first heights recorded at this
  width, kept until the width changes, so that recording more heights doesn't move every row
  below them; 0 before any. -/
  est : Nat := 0
deriving Repr, BEq, DecidableEq, Inhabited

/-- What a laid virtual list says of itself (`Style.rows`), for the runtime to record and the
fuzzer to check: what the view read, the heights it laid out by, and the window it laid. -/
structure Info where
  /-- What the runtime knew when the view ran (`UI.listOf`). -/
  known : Known
  /-- The known heights for these keys (`VList.model`): `known.rows` moved to the keys' indices. -/
  model : Array Row
  keys : Array Nat
  /-- The estimate the view was given, if any, and the one it used. -/
  estimate : Option Nat
  est : Nat
  overscan : Nat
  viewport : Int
  /-- The rows laid: indices `[first, last)`. -/
  first : Nat
  last : Nat
deriving Repr, BEq, Inhabited

end VList

-- region: node-style
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
  corner : Corner := .circular
  /-- Painted under the box's background. -/
  shadow : Option Shadow := none
  /-- Host-drawn pixels over the background, under the children. -/
  paint : Option Paint := none
  /-- A loaded image over the background (and the paint), under the children. -/
  image : Option ImageFill := none
  /-- A scroll box: `some o` lays the children out as the box's axis says,
  then moves them back by `o` points along that axis (up, or left in a row), and clips them to
  the box. `none` is an ordinary box. The children keep their real rects, possibly above or
  below the box; what shows is `rect ∩ clip` (docs/layout.md, "Scroll boxes"). -/
  scroll : Option Int := none
  /-- The scroll box's identity, when the runtime owns its offset (docs/runtime.md,
  "Scrolling"): the wheel, the trackpad and the page keys move it, and the view reads it back with
  `UI.scrollOf` (`UI.scrolling` sets both fields). Usually a `place` claim's ref. A box with
  `scroll` and no `scrollRef` scrolls only as far as the view says. -/
  scrollRef : Option ControlRef := none
  /-- A virtual list's box (`Cairn.UI.VList`): which rows it laid and the heights it laid them
  by. The runtime records the rows' real heights from it after every layout. Set by `VList.node`
  only. -/
  rows : Option VList.Info := none
deriving Repr, BEq, Inhabited
-- endregion: node-style

-- region: node-control
inductive Role where
  | group | button | checkbox | text | textField | link | list | listItem | heading | tab
  /-- A scroll box (`Style.scroll`): the frame gives one a node of its own. -/
  | scrollArea
deriving Repr, BEq, DecidableEq, Inhabited

/-- A node that performs a move. -/
structure Control where
  ref : ControlRef
  role : Role := .button
  label : String
  value : String := ""
  checked : Option Bool := none
  selected : Bool := false
  /-- Tell the app when this control comes on screen: the runtime delivers `Action.appear` when
  it has a visible part at the end of a batch and didn't at the end of the last one (or wasn't
  in the tree). How an app hears that the end of a list is in view (docs/runtime.md, "Appear"). -/
  appear : Bool := false
deriving Repr, BEq, Inhabited
-- endregion: node-control

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
  /-- A secure field (a password): `text` is one bullet per scalar of what was typed
  (`Cairn.Text.SecureField.view`), so it is drawn, measured and dumped as bullets; the frame
  marks it so the accessibility mirror shows an `AXSecureTextField` with no value and the host
  turns on secure event input while it has focus (docs/text.md, "Secure fields"). -/
  secure : Bool := false
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
  /-- Points between lines (SwiftUI's `lineSpacing`). -/
  lineSpacing : Nat := 0
deriving Repr, BEq, Inhabited

-- region: node-node
inductive Node where
  | box (style : Style) (control : Option Control) (children : List Node)
  | text (style : TextStyle) (content : String)
  /-- Text wrapped at word boundaries to the available width (`Cairn.Text.Wrap`). Layout turns
  it into a clipping column of one `text` per line, so it has no `Laid` form of its own. -/
  | para (style : TextStyle) (wrap : Wrap) (content : String)
  | field (style : Style) (text : TextStyle) (control : Control) (view : FieldView)
deriving Repr, Inhabited
-- endregion: node-node

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
-- region: node-image
/-- What an app knows of an image so far: not loaded yet, loaded (its size in pixels, from
`Reply.image`), or failed (from `Reply.failed`). -/
inductive ImageState where
  | loading
  | ready (width height : Nat)
  | failed (fault : Fault) (message : String)
deriving Repr, DecidableEq, Inhabited

/-- An image on screen (`Node.image`): where its pixels come from (a file path, `~/` for the
home folder, or an `http`/`https` URL; the host loads it for `Request.loadImage`), the box it
takes in logical points, and what is known of it so far. The box is the same in every state, so
nothing moves when the pixels arrive or fail (`Layout.measure_image`). -/
structure Image where
  source : String
  width : Nat
  height : Nat
  state : ImageState := .loading
  fit : Fit := .cover
  /-- The box while loading. -/
  placeholder : Color := ⟨229, 229, 234, 255⟩
  /-- Under a loaded image: what shows through its transparency and `contain`'s bands. -/
  backdrop : Option Color := none
  /-- The box, and the colour of its border and words, when the load failed. -/
  failedFill : Color := ⟨253, 236, 234, 255⟩
  failedInk : Color := ⟨196, 43, 28, 255⟩
deriving Repr, Inhabited

/-- The words a failed image shows. -/
def Image.faultText : Fault → String
  | .notFound => "Not found" | .denied => "No access" | .timeout => "Timed out"
  | .network => "Offline" | .invalid => "Not an image" | .other => "Failed"

/-- The image's box: `fixed` at its size in every state, clipping; the placeholder colour while
loading, the pixels once loaded, a bordered box with the fault's words when failed. -/
def Image.style (i : Image) : Style :=
  { width := .fixed i.width, height := .fixed i.height, clip := true, align := .center,
    justify := .center,
    background := match i.state with
      | .loading => some i.placeholder
      | .ready .. => i.backdrop
      | .failed .. => some i.failedFill,
    border := match i.state with
      | .failed .. => some ⟨1, i.failedInk⟩
      | _ => none,
    image := match i.state with
      | .ready w h => some { source := i.source, width := w, height := h, fit := i.fit }
      | _ => none }

/-- What a failed image says, centred in its box (clipped to it); nothing otherwise. -/
def Image.children (i : Image) : List Node :=
  match i.state with
  | .failed f _ => [.text { font := { size := 11, weight := 600 }, color := i.failedInk }
      (Image.faultText f)]
  | _ => []

/-- **An image node.** A box of the image's size whatever its state, so layout knows its size
before the pixels exist; it has no control (an image is not a move) and paints, from back to
front, its state's background, the host's pixels once loaded (`Style.image`), and a failure's
words. -/
def Node.image (i : Image) : Node := .box i.style none i.children
-- endregion: node-image

end Cairn
