module

public import Cairn.UI.Node
public import Cairn.Input
public import Cairn.Surface

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
  /-- A rounded rect with what `rect` lacks: continuous corners and a soft shadow painted under
  it (`Style.corner`, `Style.shadow`). -/
  | shape (r : Rect) (fill : Option Color) (radius : Nat) (border : Option Border)
      (corner : Corner) (shadow : Option Shadow)
  /-- Host-drawn pixels inside `r` (`Style.paint`). -/
  | paint (r : Rect) (p : Paint)
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

/-- What one Metal surface (the window, a panel) shows: M1's frame without the app-wide parts. -/
structure Canvas where
  size : Size
  draws : Array Draw
  ax : Array AxNode
  textInput : Option TextInput := none
  cursor : Cursor := .arrow
deriving Repr, Inhabited

def Canvas.empty : Canvas := { size := ⟨0, 0⟩, draws := #[], ax := #[] }

/-- The kind of a menu record: `MenuItem`'s constructors. -/
inductive MenuKind where
  | item | info | submenu | separator
deriving Repr, DecidableEq, Inhabited

/-- One `MenuItem`, flattened (`Frame.ofMenu`): parents come before their children, and
`parent` is the index of the enclosing submenu's record. -/
structure MenuRecord where
  kind : MenuKind
  label : String := ""
  /-- The item's control (`item` only). -/
  control : Option ControlRef := none
  /-- The submenu's place claim (`submenu` only, when it has one). -/
  place : Option ClaimId := none
  parent : Option Nat := none
  enabled : Bool := true
  checked : Option Bool := none
  shortcut : Option Shortcut := none
deriving Repr, Inhabited

/-- What a status item shows: its button and its menu. -/
structure StatusFrame where
  control : ControlRef := ⟨0, 0⟩
  symbol : String := ""
  title : String := ""
  label : String := ""
  menu : Array MenuRecord := #[]
deriving Repr, Inhabited

inductive SurfaceKind where
  | window | panel | statusItem
deriving Repr, DecidableEq, Inhabited

/-- One surface's record. Fields a kind doesn't use stay at their defaults: a window has no
anchor or status, a status item no canvas, a hidden surface neither. -/
structure SurfaceFrame where
  kind : SurfaceKind
  place : ClaimId
  shown : Bool := true
  /-- The window's title. -/
  title : String := ""
  /-- A panel's placement. -/
  anchor : Anchor := .bottomCenter 0
  screen : ScreenChoice := .pointer
  /-- A window's or panel's content. A panel's `size` is Lean's: its width and laid-out
  height. -/
  canvas : Canvas := Canvas.empty
  /-- A status item's button and menu. -/
  status : StatusFrame := {}
deriving Repr, Inhabited

/-- One frame: every surface of the app, in the app's order, then what is the app's as a whole.
-/
structure Frame where
  surfaces : Array SurfaceFrame
  effects : Array Effect := #[]
  /-- Subscriptions to start and stop, in order (docs/effects.md). -/
  subs : Array SubCmd := #[]
  /-- The earliest timer deadline, in the host's monotonic milliseconds: the host sends a
  `clock` event no later than this. -/
  wake : Option Nat := none
deriving Repr, Inhabited

namespace Frame

/-- A frame with one window (place 0) showing `c`: M1's frame. -/
def single (c : Canvas) (effects : Array Effect := #[]) (subs : Array SubCmd := #[])
    (wake : Option Nat := none) : Frame :=
  { surfaces := #[{ kind := .window, place := 0, canvas := c }], effects, subs, wake }

/-- The first window's canvas; empty when the frame has no window. -/
def window (f : Frame) : Canvas :=
  ((f.surfaces.find? (·.kind == .window)).map (·.canvas)).getD Canvas.empty

def size (f : Frame) : Size := f.window.size
def draws (f : Frame) : Array Draw := f.window.draws
def ax (f : Frame) : Array AxNode := f.window.ax
def textInput (f : Frame) : Option TextInput := f.window.textInput
def cursor (f : Frame) : Cursor := f.window.cursor

end Frame

end Cairn
