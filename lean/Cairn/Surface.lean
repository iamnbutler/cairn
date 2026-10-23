module

public import Cairn.UI.Node
public import Cairn.Input

/-! What an app shows besides a window (docs/surfaces.md): a menu bar status item with its
native menu, and a non-activating, click-through overlay panel, both as data. `Cairn.App`
collects an app's surfaces; the runtime keeps what each one shows (`Cairn.Runtime.Shown`) and
the frame carries it (docs/frame.md, surface records).

The menu is a description, not a laid tree: the host builds a real `NSMenu` from it, and every
actionable item is a `Control` naming a move, so presence, enablement and checkmarks are facts
about this value (`refs`, `enabledOf`, `checkedOf`) with no layout in between.

`MenuItem` is a nested inductive, so every function over it is a structural pair (`f` on one
item, `fs` on a list), per AGENTS.md. -/

@[expose] public section

namespace Cairn

/-- A keyboard shortcut shown on a menu item (⌘Q). Honoured by AppKit only while the menu is
open: an accessory app has no main menu. -/
structure Shortcut where
  key : Key
  mods : Mods := { command := true }
deriving Repr, DecidableEq, Inhabited

inductive MenuItem where
  /-- An item that performs a move. `control.checked = some b` makes it a checkbox item;
  `enabled = false` greys it out (it stays in the menu, with its control). -/
  | item (control : Control) (enabled : Bool := true) (shortcut : Option Shortcut := none)
  /-- A line of text that does nothing: a status line, "None yet". Shown disabled. -/
  | info (label : String)
  /-- A submenu. `place` is the place claim it is, if it has one. -/
  | submenu (label : String) (place : Option ClaimId) (items : List MenuItem)
  | separator
deriving Repr, Inhabited

namespace MenuItem

/-- A plain item for `r`. -/
def button (r : ControlRef) (label : String) (enabled : Bool := true)
    (shortcut : Option Shortcut := none) : MenuItem :=
  .item { ref := r, label } enabled shortcut

/-- A checkbox item for `r`, ticked when `on`. -/
def check (r : ControlRef) (label : String) (on : Bool) (enabled : Bool := true) : MenuItem :=
  .item { ref := r, role := .checkbox, label, checked := some on } enabled

mutual
/-- The refs of an item's actionable items, depth first, in menu order. -/
def refsOf : MenuItem → List ControlRef
  | .item c .. => [c.ref]
  | .submenu _ _ kids => refs kids
  | .info _ | .separator => []

/-- The refs of every actionable item in a menu, depth first, in menu order. -/
def refs : List MenuItem → List ControlRef
  | [] => []
  | m :: ms => refsOf m ++ refs ms
end

mutual
/-- The refs of an item's enabled actionable items. -/
def enabledRefsOf : MenuItem → List ControlRef
  | .item c e _ => if e then [c.ref] else []
  | .submenu _ _ kids => enabledRefs kids
  | .info _ | .separator => []

/-- The refs of every enabled actionable item in a menu, in any submenu: what a selection may
press (`Cairn.Runtime.route`, `menuSelect`). -/
def enabledRefs : List MenuItem → List ControlRef
  | [] => []
  | m :: ms => enabledRefsOf m ++ enabledRefs ms
end

mutual
/-- The first actionable item with ref `r` in an item: its control and whether it is enabled. -/
def findOf (r : ControlRef) : MenuItem → Option (Control × Bool)
  | .item c e _ => if c.ref = r then some (c, e) else none
  | .submenu _ _ kids => find r kids
  | .info _ | .separator => none

/-- The first actionable item with ref `r` in a menu. -/
def find (r : ControlRef) : List MenuItem → Option (Control × Bool)
  | [] => none
  | m :: ms =>
    match findOf r m with
    | some x => some x
    | none => find r ms
end

/-- Whether the item for `r` is enabled; `none` when the menu has no item for `r`. -/
def enabledOf (items : List MenuItem) (r : ControlRef) : Option Bool := (find r items).map (·.2)

/-- The item for `r`'s checkmark (`some none`: not a checkbox); `none` when there is no item. -/
def checkedOf (items : List MenuItem) (r : ControlRef) : Option (Option Bool) :=
  (find r items).map (·.1.checked)

mutual
theorem enabledRefsOf_sub (m : MenuItem) : ∀ r ∈ enabledRefsOf m, r ∈ refsOf m := by
  match m with
  | .item c e _ =>
    intro r h
    simp only [enabledRefsOf] at h
    split at h
    · simp only [List.mem_singleton] at h; simp only [refsOf, List.mem_singleton, h]
    · simp only [List.not_mem_nil] at h
  | .submenu _ _ kids =>
    intro r h; simp only [enabledRefsOf, refsOf] at h ⊢; exact enabledRefs_sub kids r h
  | .info _ | .separator => intro r h; simp only [enabledRefsOf, List.not_mem_nil] at h

theorem enabledRefs_sub (ms : List MenuItem) : ∀ r ∈ enabledRefs ms, r ∈ refs ms := by
  match ms with
  | [] => intro r h; simp only [enabledRefs, List.not_mem_nil] at h
  | m :: ms =>
    intro r h
    simp only [enabledRefs, refs, List.mem_append] at h ⊢
    rcases h with h | h
    · exact .inl (enabledRefsOf_sub m r h)
    · exact .inr (enabledRefs_sub ms r h)
end

/-- An enabled item is an item. -/
theorem mem_refs_of_enabled {ms : List MenuItem} {r : ControlRef} (h : r ∈ enabledRefs ms) :
    r ∈ refs ms := enabledRefs_sub ms r h

end MenuItem

/-- A menu bar status item and its menu. -/
structure StatusItem where
  /-- An SF Symbol name, drawn as a template image so it follows the menu bar's appearance. -/
  symbol : String
  /-- Optional text beside the symbol. -/
  title : String := ""
  /-- What VoiceOver says for the button. -/
  label : String
  /-- Opening the menu is a press on this control. -/
  control : ControlRef
  menu : List MenuItem
deriving Repr, Inhabited

/-- Where the host puts a panel on its screen. -/
inductive Anchor where
  /-- Horizontally centred, `offset` points above the bottom of the screen's visible frame
  (above the Dock). -/
  | bottomCenter (offset : Nat)
deriving Repr, DecidableEq, Inhabited

/-- The anchor's distance in points. -/
def Anchor.offset : Anchor → Nat
  | .bottomCenter o => o

/-- Which screen a panel is shown on. -/
inductive ScreenChoice where
  /-- The screen the pointer is on when the panel is shown; it stays there until hidden. -/
  | pointer
  | main
deriving Repr, DecidableEq, Inhabited

/-- What a shown panel holds. The panel's window behaviour (never key, click-through, on every
Space) is fixed by the host, not chosen here (docs/surfaces.md, docs/trusted.md). -/
structure PanelView where
  /-- Width in points; the height is the laid-out content's. -/
  width : Nat
  anchor : Anchor := .bottomCenter 56
  screen : ScreenChoice := .pointer
  content : Node
deriving Repr, Inhabited

end Cairn
