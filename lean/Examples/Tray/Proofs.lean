import Examples.Tray
import Cairn.Runtime.Proofs

/-! # Tray: menu presence, enablement and checkmarks

M1 proved presence and enablement through layout and hit testing; a native menu has no layout
in between (docs/surfaces.md, section 1), so these are facts about the description `menu s`, for
every state. The frame's menu records carry exactly these refs and enabled refs
(`Frame.controls_ofMenu`, `Frame.enabled_ofMenu`), and a selection is pressed only when it is an
enabled item of the menu being shown (`Runtime.menu_select_stale`). That AppKit reports the item
the person chose is an assumption (docs/trusted.md, ^941). -/

namespace Examples.Tray
open Cairn

theorem refs_itemsFrom (k : Nat) (ts : List String) :
    MenuItem.refs (itemsFrom k ts) = (List.range' k ts.length).map recentRef := by
  induction ts generalizing k with
  | nil => rfl
  | cons t ts ih =>
    simp only [itemsFrom, MenuItem.refs, MenuItem.button, MenuItem.refsOf, ih, List.length_cons,
      List.range'_succ, List.map_cons, List.singleton_append]

theorem enabledRefs_itemsFrom (k : Nat) (ts : List String) :
    MenuItem.enabledRefs (itemsFrom k ts) = (List.range' k ts.length).map recentRef := by
  induction ts generalizing k with
  | nil => rfl
  | cons t ts ih =>
    simp only [itemsFrom, MenuItem.enabledRefs, MenuItem.button, MenuItem.enabledRefsOf,
      ↓reduceIte, ih, List.length_cons, List.range'_succ, List.map_cons, List.singleton_append]

/-- The recent items' refs: ^457 keyed 0, 1, … one per item. -/
def recentRefs (s : State) : List ControlRef := (List.range' 0 s.recent.length).map recentRef

theorem refs_recentItems (s : State) : MenuItem.refs (recentItems s) = recentRefs s := by
  unfold recentItems recentRefs
  split
  · rename_i h
    simp only [List.isEmpty_iff] at h
    simp only [h, List.length_nil, List.range'_zero, List.map_nil]; rfl
  · exact refs_itemsFrom 0 s.recent

theorem enabledRefs_recentItems (s : State) :
    MenuItem.enabledRefs (recentItems s) = recentRefs s := by
  unfold recentItems recentRefs
  split
  · rename_i h
    simp only [List.isEmpty_iff] at h
    simp only [h, List.length_nil, List.range'_zero, List.map_nil]; rfl
  · exact enabledRefs_itemsFrom 0 s.recent

/-- **Presence.** In every state the menu's actionable items are exactly Show/Hide Overlay,
Keep Recent Items, Add Item, one item per recent item, Clear Recent Items and Quit Tray, in
that order. -/
theorem menu_refs (s : State) :
    MenuItem.refs (menu s) =
      [overlayRef, keepRef, addRef] ++ recentRefs s ++ [clearRef, quitRef] := by
  simp only [menu, MenuItem.refs, MenuItem.refsOf, MenuItem.button, MenuItem.check,
    MenuItem.refs_append, refs_recentItems, List.append_assoc, List.nil_append, List.cons_append,
    List.append_nil]

/-- **Enablement.** The enabled items are the same, except that Add Item is enabled exactly
while Keep Recent Items is on, and Clear Recent Items exactly when there are recent items. -/
theorem menu_enabledRefs (s : State) :
    MenuItem.enabledRefs (menu s) =
      [overlayRef, keepRef] ++ (if s.keep then [addRef] else []) ++ recentRefs s ++
        (if s.recent.isEmpty then [] else [clearRef]) ++ [quitRef] := by
  simp only [menu, MenuItem.enabledRefs, MenuItem.enabledRefsOf, MenuItem.button,
    MenuItem.check, ↓reduceIte, MenuItem.enabledRefs_append, enabledRefs_recentItems,
    List.append_assoc, List.nil_append, List.cons_append, List.append_nil]
  cases s.keep <;> cases s.recent.isEmpty <;> rfl

/-- Quit Tray is always there and always enabled. -/
theorem quit_enabled (s : State) : quitRef ∈ MenuItem.enabledRefs (menu s) := by
  simp only [menu_enabledRefs, List.mem_append, List.mem_singleton, or_true]

/-- Add Item is in the menu in every state, greyed out while Keep Recent Items is off. -/
theorem add_present (s : State) : addRef ∈ MenuItem.refs (menu s) := by
  simp only [menu_refs, List.mem_append, List.mem_cons, true_or, or_true]

theorem add_enabled_iff (s : State) : addRef ∈ MenuItem.enabledRefs (menu s) ↔ s.keep = true := by
  have h1 : addRef ∉ recentRefs s := by
    simp only [recentRefs, List.mem_map, recentRef, addRef, ControlRef.mk.injEq, not_exists,
      not_and]
    intro _ _ h; exact absurd h (by decide)
  rw [menu_enabledRefs]
  cases s.keep <;> cases s.recent.isEmpty <;>
    simp only [↓reduceIte, Bool.false_eq_true, List.mem_append, List.mem_cons,
      List.not_mem_nil, h1, or_false, iff_true, iff_false] <;>
    decide

/-- Keep Recent Items carries its checkmark: ticked exactly when the setting is on. -/
theorem keep_checked (s : State) :
    MenuItem.checkedOf (menu s) keepRef = some (some s.keep) := by
  simp only [MenuItem.checkedOf, menu, MenuItem.find, MenuItem.findOf, MenuItem.button,
    MenuItem.check, overlayRef, keepRef, ControlRef.mk.injEq, and_true, ↓reduceIte,
    Nat.reduceEqDiff, Option.map_some]

/-- Opening the menu is a press on ^453. -/
theorem status_control (s : State) : (statusItem s).control = openRef := rfl

/-! ## Through the runtime -/

open Runtime in
/-- The status item the runtime shows is the menu of the current state. -/
theorem statusOf_shows (cfg : Config) (st : State) :
    Shown.statusOf 450 (shows app cfg st) = some (statusItem st) := rfl

open Runtime in
/-- **A greyed-out item can't be chosen.** In every state the running app reaches, after any
input, choosing Add Item while Keep Recent Items is off (the host reporting it, say, because the
menu changed while it was open) changes nothing at all. -/
theorem add_ignored_when_off (cfg : Config) (size : Size) (scale : Nat) (es : List Event)
    (h : (steps app cfg (start app cfg size scale) es).1.app.keep = false) :
    let s := (steps app cfg (start app cfg size scale) es).1
    step app cfg s (.menuSelect 450 addRef) = (s, []) := by
  intro s
  apply menu_select_stale
  intro it hit
  rw [steps_surfaces app cfg es _ (start_surfaces app cfg size scale), statusOf_shows] at hit
  cases hit
  intro hm
  have := (add_enabled_iff _).1 hm
  rw [h] at this
  cases this

end Examples.Tray
