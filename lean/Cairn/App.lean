module

public import Cairn.UI.Node
public import Cairn.Input
public import Cairn.Claim
public import Cairn.Surface
public import Cairn.Font

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
  /-- The offset of each scroll box that has scrolled, by its `Style.scrollRef`. The runtime
  moves them (the wheel, the trackpad, the page keys, Tab into a box) and clamps them to the box's
  content; the view reads them with `scrollOf` (docs/runtime.md, "Scrolling"). -/
  scroll : List (ControlRef × Int) := []
  /-- What the runtime knows of each virtual list on screen, by its `scrollRef`: the heights of
  the rows it has laid, and the anchor (docs/runtime.md, "Virtual lists"). The runtime records
  them after every layout; `VList.node` reads them. -/
  lists : List (ControlRef × VList.Known) := []
  /-- The offsets of scroll boxes that are not on screen and that the app keeps
  (`App.keepScroll`), as they were when they left: the view reads them with `scrollOf` when the
  box comes back (docs/runtime.md, "Scrolling"). -/
  kept : List (ControlRef × Int) := []
  /-- What the runtime knew of each virtual list not on screen that the app keeps, likewise. -/
  keptLists : List (ControlRef × VList.Known) := []
  /-- The control whose menu (`Style.menu`) is open now, if one is: the runtime opens it (a
  secondary click, a menu button, the context-menu key) and closes it when the host says the
  native menu closed, an item was chosen, or the control or its menu is gone. A view may read it
  (a ⋯ button drawn pressed while its menu is open). -/
  menu : Option ControlRef := none
deriving Repr, DecidableEq, Inhabited

/-- What the runtime knows of the virtual list `r`: nothing until it has been laid. A list the
app keeps (`App.keepScroll`) is known while it is not on screen too. -/
def UI.listOf (ui : UI) (r : ControlRef) : VList.Known :=
  match ui.lists.find? (·.1 == r) with
  | some (_, k) => k
  | none =>
    match ui.keptLists.find? (·.1 == r) with
    | some (_, k) => k
    | none => {}

/-- The runtime's offset for the scroll box `r`: 0 until it has scrolled. A box the app keeps
(`App.keepScroll`) keeps its offset while it is not on screen. -/
def UI.scrollOf (ui : UI) (r : ControlRef) : Int :=
  match ui.scroll.find? (·.1 == r) with
  | some (_, o) => o
  | none =>
    match ui.kept.find? (·.1 == r) with
    | some (_, o) => o
    | none => 0

/-- `st` as the scroll box `r` whose offset the runtime owns: scrolled by `ui.scrollOf r`.

```lean
example : (({} : UI).scrolling ⟨14, 0⟩ {}).scroll = some 0 := rfl
```
-/
def UI.scrolling (ui : UI) (r : ControlRef) (st : Style) : Style :=
  { st with scroll := some (ui.scrollOf r), scrollRef := some r }

-- region: app-surface
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
  /-- The app's own items in the main menu bar (docs/surfaces.md, "The app's menus"). A top-level
  `submenu` is a menu of its own in the menu bar, after the app menu, in order (Go, View); every
  other top-level entry goes in the app menu, after the app's name and before Hide and Quit,
  which stay the host's. An item's shortcut is its key equivalent, honoured whenever the app is
  active. Shown only while the app has a window: an accessory app has no main menu. -/
  | menuBar (place : ClaimId) (view : S → List MenuItem)
-- endregion: app-surface

namespace Surface

variable {S T : Type}

def place : Surface S → ClaimId
  | .window p .. | .panel p _ | .statusItem p _ | .menuBar p _ => p

/-- The same surface over a bigger state (`Cairn.Runtime.logged` wraps an app's state). -/
def comap (f : T → S) : Surface S → Surface T
  | .window p t v => .window p t (fun s ui => v (f s) ui)
  | .panel p v => .panel p (fun m s => v m (f s))
  | .statusItem p v => .statusItem p (fun s => v (f s))
  | .menuBar p v => .menuBar p (fun s => v (f s))

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
    | menuBar p v => simp only [List.map_cons, Surface.comap, firstWindow]; exact ih

/-- What an app with no window lays out as its window: nothing. -/
def emptyView : Node := .box {} none []

-- region: app-app
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
  /-- How many requests of capped kinds (`Request.Kind.capped`: `http`, `upload`, `loadImage`)
  may be with the host at once (at least 1). The runtime queues the rest (docs/effects.md,
  "Requests in flight"). -/
  maxInFlight : Nat := 6
  /-- The window's smallest content size in this state, in points. The host keeps the window
  at least this big, so a person can't drag it smaller (`NSWindow.contentMinSize`; trusted,
  ^1010), and the view can be proved good at every size from it up (with `Grid.minBox`, for
  instance). `0 × 0`, no minimum, by default. -/
  minSize : S → Size := fun _ => ⟨0, 0⟩
  /-- The scroll boxes and virtual lists (by `Style.scrollRef`) whose offset, and what the
  runtime knows of their rows, outlive their leaving the view in this state: a list on a tab not
  shown comes back where it was. Any other box's offset is forgotten when it leaves the tree
  (docs/runtime.md, "Scrolling"). None by default. -/
  keepScroll : S → List ControlRef := fun _ => []
-- endregion: app-app

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
