module

public import Cairn.UI.Node
public import Cairn.Input
public import Cairn.Claim
public import Cairn.Surface
public import Cairn.Text.Metrics

/-! An app is its state, its surfaces, and its moves. The runtime (`Cairn.Runtime`) owns
interaction state (hover, press, focus, window size), turns events into actions by hit testing
the laid-out frame or checking the menu, and calls `update`. -/

@[expose] public section


namespace Cairn

/-- Interaction state the runtime owns and the view may read (hover reveals, focus rings). -/
structure UI where
  size : Size := ⟨800, 600⟩
  hover : Option ControlRef := none
  pressed : Option ControlRef := none
  focus : Option ControlRef := none
  windowFocused : Bool := true
deriving Repr, DecidableEq, Inhabited

/-- One thing an app shows (docs/surfaces.md). An app declares a fixed list of them; whether
each is shown, and what it shows, is a function of the state. `place` is the surface's place
claim: its durable identity on the wire, in the map and in the debug socket. -/
inductive Surface (S : Type) where
  /-- M1's window: Metal content laid out at the window's size, with input. -/
  | window (place : ClaimId) (title : String) (view : S → UI → Node)
  /-- A non-activating, click-through overlay panel; `none` hides it. It takes no input, so its
  view doesn't read `UI`. The view is given the text metrics the panel is laid out with, so it
  can measure content (`Cairn.Layout.measure`), for instance to animate between two heights. -/
  | panel (place : ClaimId) (view : TextMetrics → S → Option PanelView)
  /-- A menu bar status item and its native menu; `none` removes it from the menu bar. -/
  | statusItem (place : ClaimId) (view : S → Option StatusItem)

namespace Surface

variable {S T : Type}

def place : Surface S → ClaimId
  | .window p .. | .panel p _ | .statusItem p _ => p

/-- The same surface over a bigger state (`Cairn.Runtime.logged` wraps an app's state). -/
def comap (f : T → S) : Surface S → Surface T
  | .window p t v => .window p t (fun s ui => v (f s) ui)
  | .panel p v => .panel p (fun m s => v m (f s))
  | .statusItem p v => .statusItem p (fun s => v (f s))

@[simp] theorem place_comap (f : T → S) (x : Surface S) : (x.comap f).place = x.place := by
  cases x <;> rfl

end Surface

/-- The first window in a surface list: its place, title and view. -/
def firstWindow {S : Type} : List (Surface S) → Option (ClaimId × String × (S → UI → Node))
  | [] => none
  | .window p t v :: _ => some (p, t, v)
  | _ :: xs => firstWindow xs

theorem firstWindow_comap {S T : Type} (f : T → S) (xs : List (Surface S)) :
    firstWindow (xs.map (Surface.comap f)) =
      (firstWindow xs).map (fun (p, t, v) => (p, t, fun s ui => v (f s) ui)) := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    cases x with
    | window p t v => rfl
    | panel p v => simp only [List.map_cons, Surface.comap, firstWindow]; exact ih
    | statusItem p v => simp only [List.map_cons, Surface.comap, firstWindow]; exact ih

/-- What an app with no window lays out as its window: nothing. -/
def emptyView : Node := .box {} none []

structure App (S : Type) where
  init : S
  /-- What the app shows: at most one window (a later window is ignored), panels and status
  items. An app with no window is an accessory app (no Dock icon, no main menu). -/
  surfaces : List (Surface S)
  /-- A person's moves: every action names a control on screen. -/
  update : S → Action → S × List Effect
  /-- The outside world: the clock, timers, replies and subscription events
  (docs/effects.md). Ignored by default. -/
  receive : S → Msg → S × List Effect := fun s _ => (s, [])
  /-- The outside inputs the app wants in this state. The runtime diffs them after every
  delivery and starts and stops subscriptions to match. -/
  subscriptions : S → List Sub := fun _ => []
  /-- Effects to run once, when the first clock arrives (so timers start from a real time). -/
  initEffects : List Effect := []
  /-- Every claim the app makes, from the claim commands. -/
  claims : List ClaimInfo
  /-- The control that has keyboard focus at launch, if it is focusable there. -/
  initFocus : Option ControlRef := none

namespace App

variable {S : Type}

/-- The window's view, as M1's `App.view` was; an empty box when there is no window. Every M1
theorem about `view` is about this. -/
def view (app : App S) : S → UI → Node :=
  match firstWindow app.surfaces with
  | some (_, _, v) => v
  | none => fun _ _ => emptyView

/-- The window's place claim, if the app has a window. Bare surface-local events (M1's) go to
this window. -/
def windowPlace (app : App S) : Option ClaimId := (firstWindow app.surfaces).map (·.1)

/-- The view of an app whose surfaces are `app`'s over a bigger state reads the smaller one. -/
theorem view_comap (app : App S) {T : Type} (f : T → S) (b : App T)
    (h : b.surfaces = app.surfaces.map (Surface.comap f)) (s : T) (ui : UI) :
    b.view s ui = app.view (f s) ui := by
  unfold view
  rw [h, firstWindow_comap]
  cases firstWindow app.surfaces <;> rfl

/-- An app with no window runs as an accessory (docs/surfaces.md, section 3). -/
def accessory (app : App S) : Bool := (firstWindow app.surfaces).isNone

end App

end Cairn

/-- `==` on `UI` is the lawful one from `DecidableEq`, so proofs can use it. -/
example : LawfulBEq Cairn.UI := inferInstance
