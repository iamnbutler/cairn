module

public import Cairn.Frame

/-! `Frame.ofMenu`: a status item's menu description becomes the flat list of menu records the
frame carries (docs/frame.md, "Menu records"), parents before children, as the accessibility
list is.

Theorems: `controls_ofMenu` (the records' controls are exactly the description's actionable
items, in order: what the host's `NSMenu` is built from is what the presence and enablement
proofs are about), `enabled_ofMenu` (likewise for the enabled ones) and `parent_lt_ofMenu`
(every parent index points at an earlier record, and at a submenu). -/

@[expose] public section

namespace Cairn

namespace Frame

/-- The record for one item, without its children. -/
def menuRecord (parent : Option Nat) : MenuItem → MenuRecord
  | .item c e sc =>
    { kind := .item, label := c.label, control := some c.ref, parent, enabled := e,
      checked := c.checked, shortcut := sc }
  | .info l => { kind := .info, label := l, parent, enabled := false }
  | .submenu l p _ => { kind := .submenu, label := l, place := p, parent }
  | .separator => { kind := .separator, parent, enabled := false }

mutual
/-- Append the records of an item (and, for a submenu, its children) to `acc`. -/
def menuOf (parent : Option Nat) (acc : Array MenuRecord) : MenuItem → Array MenuRecord
  | .submenu l p kids =>
    menuAll (some acc.size) (acc.push (menuRecord parent (.submenu l p kids))) kids
  | m => acc.push (menuRecord parent m)

def menuAll (parent : Option Nat) (acc : Array MenuRecord) : List MenuItem → Array MenuRecord
  | [] => acc
  | m :: ms => menuAll parent (menuOf parent acc m) ms
end

/-- A menu description, flattened. -/
def ofMenu (items : List MenuItem) : Array MenuRecord := menuAll none #[] items

/-- What a status item puts on the frame. -/
def ofStatus (it : StatusItem) : StatusFrame :=
  { control := it.control, symbol := it.symbol, title := it.title, label := it.label,
    menu := ofMenu it.menu }

/-- The control of an actionable record. -/
def MenuRecord.ctl (r : MenuRecord) : Option ControlRef := r.control

/-- The control of an enabled actionable record. -/
def MenuRecord.enabledCtl (r : MenuRecord) : Option ControlRef :=
  if r.enabled then r.control else none

/-! ## The records' controls are the description's -/

mutual
theorem menuOf_controls (parent : Option Nat) (acc : Array MenuRecord) (m : MenuItem) :
    (menuOf parent acc m).toList.filterMap MenuRecord.ctl =
      acc.toList.filterMap MenuRecord.ctl ++ MenuItem.refsOf m := by
  match m with
  | .submenu l p kids =>
    rw [menuOf, menuAll_controls]
    simp only [Array.toList_push, List.filterMap_append, List.filterMap_cons, menuRecord, MenuRecord.ctl,
      List.filterMap_nil, List.append_nil, MenuItem.refsOf]
  | .item c e sc =>
    simp only [menuOf, Array.toList_push, List.filterMap_append, List.filterMap_cons, menuRecord, MenuRecord.ctl,
      List.filterMap_nil, MenuItem.refsOf]
  | .info l =>
    simp only [menuOf, Array.toList_push, List.filterMap_append, List.filterMap_cons, menuRecord, MenuRecord.ctl,
      List.filterMap_nil, MenuItem.refsOf, List.append_nil]
  | .separator =>
    simp only [menuOf, Array.toList_push, List.filterMap_append, List.filterMap_cons, menuRecord, MenuRecord.ctl,
      List.filterMap_nil, MenuItem.refsOf, List.append_nil]

theorem menuAll_controls (parent : Option Nat) (acc : Array MenuRecord) (ms : List MenuItem) :
    (menuAll parent acc ms).toList.filterMap MenuRecord.ctl =
      acc.toList.filterMap MenuRecord.ctl ++ MenuItem.refs ms := by
  match ms with
  | [] => simp only [menuAll, MenuItem.refs, List.append_nil]
  | m :: ms =>
    rw [menuAll, menuAll_controls, menuOf_controls]
    simp only [MenuItem.refs, List.append_assoc]
end

/-- **The menu on the frame is the menu described.** The controls of the frame's menu records
are exactly the description's actionable items, in order. -/
theorem controls_ofMenu (items : List MenuItem) :
    (ofMenu items).toList.filterMap MenuRecord.ctl = MenuItem.refs items := by
  simp only [ofMenu, menuAll_controls, List.filterMap_nil, List.nil_append]

mutual
theorem menuOf_enabled (parent : Option Nat) (acc : Array MenuRecord) (m : MenuItem) :
    (menuOf parent acc m).toList.filterMap MenuRecord.enabledCtl =
      acc.toList.filterMap MenuRecord.enabledCtl ++ MenuItem.enabledRefsOf m := by
  match m with
  | .submenu l p kids =>
    rw [menuOf, menuAll_enabled]
    simp only [Array.toList_push, List.filterMap_append, List.filterMap_cons, menuRecord, MenuRecord.enabledCtl,
      ite_true, List.filterMap_nil, List.append_nil,
      MenuItem.enabledRefsOf]
  | .item c e sc =>
    cases e <;>
    simp only [menuOf, Array.toList_push, List.filterMap_append, List.filterMap_cons, menuRecord,
      MenuRecord.enabledCtl, ite_true, Bool.false_eq_true, ite_false,
      List.filterMap_nil, MenuItem.enabledRefsOf, List.append_nil]
  | .info l =>
    simp only [menuOf, Array.toList_push, List.filterMap_append, List.filterMap_cons, menuRecord,
      MenuRecord.enabledCtl, Bool.false_eq_true, ite_false,
      List.filterMap_nil, MenuItem.enabledRefsOf, List.append_nil]
  | .separator =>
    simp only [menuOf, Array.toList_push, List.filterMap_append, List.filterMap_cons, menuRecord,
      MenuRecord.enabledCtl, Bool.false_eq_true, ite_false,
      List.filterMap_nil, MenuItem.enabledRefsOf, List.append_nil]

theorem menuAll_enabled (parent : Option Nat) (acc : Array MenuRecord) (ms : List MenuItem) :
    (menuAll parent acc ms).toList.filterMap MenuRecord.enabledCtl =
      acc.toList.filterMap MenuRecord.enabledCtl ++ MenuItem.enabledRefs ms := by
  match ms with
  | [] => simp only [menuAll, MenuItem.enabledRefs, List.append_nil]
  | m :: ms =>
    rw [menuAll, menuAll_enabled, menuOf_enabled]
    simp only [MenuItem.enabledRefs, List.append_assoc]
end

/-- The enabled records' controls are exactly the description's enabled items: what the host
greys out is what Lean will refuse (`Runtime.menu_select_stale`). -/
theorem enabled_ofMenu (items : List MenuItem) :
    (ofMenu items).toList.filterMap MenuRecord.enabledCtl = MenuItem.enabledRefs items := by
  simp only [ofMenu, menuAll_enabled, List.filterMap_nil, List.nil_append]

/-! ## Parents point backwards, at submenus -/

/-- Every record's parent is an earlier record, and a submenu. -/
def MenuParentsOk (ms : Array MenuRecord) : Prop :=
  ∀ i (h : i < ms.size) p, ms[i].parent = some p → ∃ hp : p < i, ms[p].kind = .submenu

def MenuParentBelow (ms : Array MenuRecord) (parent : Option Nat) : Prop :=
  ∀ p, parent = some p → ∃ hp : p < ms.size, ms[p].kind = .submenu

theorem MenuParentBelow.push {ms : Array MenuRecord} {parent : Option Nat}
    (h : MenuParentBelow ms parent) (x : MenuRecord) : MenuParentBelow (ms.push x) parent := by
  intro p hp
  obtain ⟨hlt, hk⟩ := h p hp
  exact ⟨by simp only [Array.size_push]; omega, by rw [Array.getElem_push_lt hlt]; exact hk⟩

theorem MenuParentsOk.push {ms : Array MenuRecord} {x : MenuRecord} (h : MenuParentsOk ms)
    (hx : MenuParentBelow ms x.parent) : MenuParentsOk (ms.push x) := by
  intro i hi p hp
  rw [Array.size_push] at hi
  by_cases hlt : i < ms.size
  · rw [Array.getElem_push_lt hlt] at hp
    obtain ⟨hpi, hk⟩ := h i hlt p hp
    exact ⟨hpi, by rw [Array.getElem_push_lt (Nat.lt_trans hpi hlt)]; exact hk⟩
  · have : i = ms.size := by omega
    subst this
    rw [Array.getElem_push_eq] at hp
    obtain ⟨hpi, hk⟩ := hx p hp
    exact ⟨hpi, by rw [Array.getElem_push_lt hpi]; exact hk⟩

-- Records only get appended: what was below stays below.
mutual
theorem menuOf_prefix (parent : Option Nat) (acc : Array MenuRecord) (m : MenuItem) :
    ∃ hs : acc.size ≤ (menuOf parent acc m).size,
      ∀ i (hi : i < acc.size), (menuOf parent acc m)[i]'(Nat.lt_of_lt_of_le hi hs) = acc[i] := by
  match m with
  | .submenu l p kids =>
    rw [menuOf]
    obtain ⟨hs, he⟩ := menuAll_prefix (some acc.size)
      (acc.push (menuRecord parent (.submenu l p kids))) kids
    refine ⟨Nat.le_trans (by simp only [Array.size_push, Nat.le_add_right]) hs, fun i hi => ?_⟩
    rw [he i (by simp only [Array.size_push]; omega), Array.getElem_push_lt hi]
  | .item .. | .info _ | .separator =>
    refine ⟨by simp only [menuOf, Array.size_push, Nat.le_add_right], fun i hi => ?_⟩
    simp only [menuOf, Array.getElem_push_lt hi]

theorem menuAll_prefix (parent : Option Nat) (acc : Array MenuRecord) (ms : List MenuItem) :
    ∃ hs : acc.size ≤ (menuAll parent acc ms).size,
      ∀ i (hi : i < acc.size), (menuAll parent acc ms)[i]'(Nat.lt_of_lt_of_le hi hs) = acc[i] := by
  match ms with
  | [] => exact ⟨by simp only [menuAll, Nat.le_refl], fun i hi => by simp only [menuAll]⟩
  | m :: ms =>
    obtain ⟨hs1, he1⟩ := menuOf_prefix parent acc m
    obtain ⟨hs2, he2⟩ := menuAll_prefix parent (menuOf parent acc m) ms
    refine ⟨by rw [menuAll]; exact Nat.le_trans hs1 hs2, fun i hi => ?_⟩
    simp only [menuAll]
    rw [he2 i (Nat.lt_of_lt_of_le hi hs1), he1 i hi]
end

theorem MenuParentBelow.mono {ms ms' : Array MenuRecord} {parent : Option Nat}
    (h : MenuParentBelow ms parent) (hs : ms.size ≤ ms'.size)
    (he : ∀ i (hi : i < ms.size), ms'[i]'(Nat.lt_of_lt_of_le hi hs) = ms[i]) :
    MenuParentBelow ms' parent := by
  intro p hp
  obtain ⟨hlt, hk⟩ := h p hp
  exact ⟨Nat.lt_of_lt_of_le hlt hs, by rw [he p hlt]; exact hk⟩

mutual
theorem menuOf_parents (parent : Option Nat) (acc : Array MenuRecord) (m : MenuItem)
    (h : MenuParentsOk acc) (hp : MenuParentBelow acc parent) :
    MenuParentsOk (menuOf parent acc m) := by
  match m with
  | .submenu l p kids =>
    rw [menuOf]
    apply menuAll_parents
    · exact h.push (x := menuRecord parent (.submenu l p kids)) hp
    · intro q hq
      simp only [Option.some.injEq] at hq
      subst hq
      exact ⟨by simp only [Array.size_push, Nat.lt_add_one],
        by simp only [Array.getElem_push_eq, menuRecord]⟩
  | .item c e sc => exact h.push (x := menuRecord parent (.item c e sc)) hp
  | .info l => exact h.push (x := menuRecord parent (.info l)) hp
  | .separator => exact h.push (x := menuRecord parent .separator) hp

theorem menuAll_parents (parent : Option Nat) (acc : Array MenuRecord) (ms : List MenuItem)
    (h : MenuParentsOk acc) (hp : MenuParentBelow acc parent) :
    MenuParentsOk (menuAll parent acc ms) := by
  match ms with
  | [] => simp only [menuAll]; exact h
  | m :: ms =>
    rw [menuAll]
    obtain ⟨hs, he⟩ := menuOf_prefix parent acc m
    exact menuAll_parents _ _ _ (menuOf_parents _ _ _ h hp) (hp.mono hs he)
end

/-- **Parents first.** Every menu record's parent is an earlier record and a submenu, so the
host builds the `NSMenu` tree in one pass. -/
theorem parent_lt_ofMenu (items : List MenuItem) : MenuParentsOk (ofMenu items) :=
  menuAll_parents _ _ _ (fun i h => by simp only [List.size_toArray, List.length_nil,
      Nat.not_lt_zero] at h) (fun _ h => by simp only [reduceCtorEq] at h)

end Frame

end Cairn
