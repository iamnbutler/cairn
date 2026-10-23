import Examples.Todo
import Cairn.Layout
import Cairn.Layout.Rigid
import Cairn.Frame.Layout
import Cairn.Runtime
import Cairn.Claims.Deliver

/-! # TodoMVC: presence and pressability

The moves' own evidence (`post` for every enabled state), the invariants ^212 and ^213 and the
flows ^216–^224 are checked where they are declared, in `Examples.Todo`. This file proves what
depends on the view and layout:

- **presence** (M1, docs/goals/m1.md): a control tagged with a move's id is in the view, and so in every
  frame's accessibility tree, exactly when the move is enabled. The keyed moves follow from one
  lemma about keyed lists (`mem_flatMap_keyed`).
- **pressable**: in a window at least `minWidth` wide and `height s` tall, with **any** text
  metrics, hit testing at the centre of an enabled move's control returns that control. The
  view is rigid (`Cairn.Layout.FitsIn`, `view_fitsIn`), so one argument covers every state.

Unkeyed moves (^202, ^203, ^208–^211) are drawn with key 0; their presence theorems are about
that ref. -/

namespace Examples.Todo
open Cairn Cairn.Claims Cairn.Layout Cairn.Runtime

/-! ## A keyed list -/

/-- **Presence in a keyed list.** If every control a row draws carries that row's key, then a
control with claim `c` and key `k` is in the list exactly when some row has key `k` and draws it.
Any app that draws one group of controls per item, keyed by the item's id, gets presence from this
and a statement about one row. -/
theorem mem_flatMap_keyed {α : Type} (xs : List α) (key : α → Nat) (rows : α → List ControlRef)
    (hk : ∀ x, ∀ r ∈ rows x, r.key = key x) (c k : Nat) :
    (⟨c, k⟩ : ControlRef) ∈ xs.flatMap rows ↔ ∃ x ∈ xs, key x = k ∧ (⟨c, k⟩ : ControlRef) ∈ rows x := by
  simp only [List.mem_flatMap]
  constructor
  · rintro ⟨x, hx, hr⟩
    exact ⟨x, hx, (hk x _ hr).symm, hr⟩
  · rintro ⟨x, hx, -, hr⟩
    exact ⟨x, hx, hr⟩

/-! ## The view's controls -/

/-- What todo `t`'s row draws: the edit field in edit mode, else checkbox, title and delete. -/
def rowRefs (s : State) (t : Todo) : List ControlRef :=
  if isEditing s t.id then [editRef t.id] else [toggleRef t.id, titleRef t.id, deleteRef t.id]

theorem rowRefs_key (s : State) (t : Todo) : ∀ r ∈ rowRefs s t, r.key = t.id := by
  unfold rowRefs
  split <;> simp only [List.mem_cons, List.not_mem_nil, or_false] <;> rintro r (rfl | rfl | rfl) <;> rfl

theorem rowRefs_claim (s : State) (t : Todo) : ∀ r ∈ rowRefs s t, 204 ≤ r.claim ∧ r.claim ≤ 207 := by
  unfold rowRefs
  split <;> simp only [List.mem_cons, List.not_mem_nil, or_false] <;> rintro r (rfl | rfl | rfl) <;>
    simp [editRef, toggleRef, titleRef, deleteRef]

theorem todoRow_refs (s : State) (ui : UI) (t : Todo) :
    (todoRow s ui t).controls.map (·.ref) = rowRefs s t := by
  unfold todoRow rowRefs isEditing editingId
  have hv : (todoRow.viewRow ui t).controls.map (·.ref) =
      [toggleRef t.id, titleRef t.id, deleteRef t.id] := by
    simp only [todoRow.viewRow, cell]
    cases t.completed <;> cases hot ui t.id <;> simp [Node.controls, Node.controlsList]
  cases he : s.editing with
  | none => simp only [hv, Option.map_none, reduceCtorEq, decide_false, Bool.false_eq_true, ↓reduceIte]
  | some e =>
    by_cases h : e.id = t.id
    · simp [h, spacer, cell, Node.controls, Node.controlsList]
    · simp only [h, ↓reduceIte, hv, Option.map_some, Option.some.injEq, decide_false,
        Bool.false_eq_true]

/-- The footer's controls: the three filters, then Clear completed when some todo is done. -/
def footRefs (s : State) : List ControlRef :=
  [filterRef .all, filterRef .active, filterRef .completed] ++ (if anyDone s then [clearRef] else [])

/-- **The view's controls**, in paint order. -/
theorem view_refs (s : State) (ui : UI) :
    (view s ui).controls.map (·.ref) =
      if s.todos.isEmpty then [newRef]
      else toggleAllRef :: newRef :: ((visible s).flatMap (rowRefs s) ++ footRefs s) := by
  have hl : (list s ui).controls.map (·.ref) = (visible s).flatMap (rowRefs s) := by
    simp only [list, Node.controls, Option.toList, List.nil_append, controlsList_map,
      List.map_flatMap, todoRow_refs]
  have hf : (footer s ui).controls.map (·.ref) = footRefs s := by
    unfold footer footRefs
    cases anyDone s <;> simp [spacer, cell, filterBox, Node.controls, Node.controlsList]
  unfold view
  cases h : s.todos.isEmpty
  · have hh : (header s ui).controls.map (·.ref) = [toggleAllRef, newRef] := by
      simp [header, h, cell, Node.controls, Node.controlsList]
    simp only [Node.controls, Option.toList, List.nil_append, Node.controlsList, heading, info,
      Bool.false_eq_true, ↓reduceIte, List.cons_append, List.append_nil, List.map_append] at hh hl hf ⊢
    simp [hh, hl, hf]
  · have hh : (header s ui).controls.map (·.ref) = [newRef] := by
      simp [header, h, spacer, cell, Node.controls, Node.controlsList]
    simp only [Node.controls, Option.toList, List.nil_append, Node.controlsList, heading, info,
      ↓reduceIte, List.cons_append, List.append_nil] at hh ⊢
    simp [hh]


/-! ## Presence -/

theorem mem_visible {s : State} {t : Todo} (h : t ∈ visible s) : t ∈ s.todos :=
  (List.mem_filter.1 h).1

theorem shown_iff (s : State) (k : Nat) : shown s k = true ↔ ∃ t ∈ visible s, t.id = k := by
  simp [shown]

theorem visible_nil {s : State} (h : s.todos.isEmpty = true) : visible s = [] := by
  simp only [visible, List.isEmpty_iff.1 h, List.filter_nil]

/-- A row control (claim `c`, not one of the header's or footer's) is in the view exactly when
a listed todo with key `k` draws it. -/
theorem row_present (s : State) (ui : UI) (c k : Nat)
    (hc : c ≠ 202 ∧ c ≠ 203 ∧ c ≠ 208 ∧ c ≠ 209 ∧ c ≠ 210 ∧ c ≠ 211) :
    (⟨c, k⟩ : ControlRef) ∈ (view s ui).controls.map (·.ref) ↔
      ∃ t ∈ visible s, t.id = k ∧ (⟨c, k⟩ : ControlRef) ∈ rowRefs s t := by
  obtain ⟨h2, h3, h8, h9, h10, h11⟩ := hc
  rw [view_refs]
  cases h : s.todos.isEmpty
  · have hf : (⟨c, k⟩ : ControlRef) ∉ footRefs s := by
      unfold footRefs
      cases anyDone s <;> simp [filterRef, clearRef, h8, h9, h10, h11]
    simp only [Bool.false_eq_true, ↓reduceIte, List.mem_cons, List.mem_append, toggleAllRef,
      newRef, ControlRef.mk.injEq, h3, h2, false_and, false_or, hf, or_false]
    exact mem_flatMap_keyed _ _ _ (rowRefs_key s) c k
  · simp only [↓reduceIte, List.mem_cons, newRef, ControlRef.mk.injEq, h2, false_and,
      List.not_mem_nil, or_false, false_iff, visible_nil h, List.not_mem_nil]
    simp

/-- The refs of the view, as a predicate. -/
abbrev InView (s : State) (ui : UI) (r : ControlRef) : Prop := r ∈ (view s ui).controls.map (·.ref)

theorem rowMove_present (s : State) (ui : UI) (c k : Nat) (hc : c = 204 ∨ c = 205 ∨ c = 206) :
    InView s ui ⟨c, k⟩ ↔ (shown s k && !isEditing s k) = true := by
  rw [InView, row_present s ui c k (by omega), Bool.and_eq_true, shown_iff]
  constructor
  · rintro ⟨t, ht, rfl, hr⟩
    refine ⟨⟨t, ht, rfl⟩, ?_⟩
    unfold rowRefs at hr
    split at hr
    · rcases hc with rfl | rfl | rfl <;> simp [editRef] at hr
    · simp [*]
  · rintro ⟨⟨t, ht, rfl⟩, he⟩
    refine ⟨t, ht, rfl, ?_⟩
    simp only [Bool.not_eq_eq_eq_not, Bool.not_true] at he
    unfold rowRefs; simp only [he, Bool.false_eq_true, ↓reduceIte]
    rcases hc with rfl | rfl | rfl <;> simp [toggleRef, titleRef, deleteRef]

theorem edit_present (s : State) (ui : UI) (k : Nat) :
    InView s ui (editRef k) ↔ (shown s k && isEditing s k) = true := by
  rw [editRef, InView, row_present s ui 207 k (by omega), Bool.and_eq_true, shown_iff]
  constructor
  · rintro ⟨t, ht, rfl, hr⟩
    refine ⟨⟨t, ht, rfl⟩, ?_⟩
    unfold rowRefs at hr
    split at hr
    · assumption
    · simp [toggleRef, titleRef, deleteRef] at hr
  · rintro ⟨⟨t, ht, rfl⟩, he⟩
    exact ⟨t, ht, rfl, by simp [rowRefs, he, editRef]⟩

theorem header_present (s : State) (ui : UI) (c : Nat) (hc : c = 203 ∨ c = 208 ∨ c = 209 ∨ c = 210) :
    InView s ui ⟨c, 0⟩ ↔ (!s.todos.isEmpty) = true := by
  rw [InView, view_refs]
  cases h : s.todos.isEmpty <;> rcases hc with rfl | rfl | rfl | rfl <;>
    simp [footRefs, filterRef, newRef, toggleAllRef, clearRef]

theorem clear_present (s : State) (ui : UI) : InView s ui clearRef ↔ anyDone s = true := by
  rw [InView, view_refs]
  cases h : s.todos.isEmpty
  · cases hd : anyDone s
    · simp only [Bool.false_eq_true, ↓reduceIte, List.mem_cons, List.mem_append, footRefs,
        iff_false]
      rintro (h | h | h | h)
      · cases h
      · cases h
      · obtain ⟨t, -, hr⟩ := List.mem_flatMap.1 h
        have := rowRefs_claim s t _ hr; simp [clearRef] at this
      · simp [filterRef, clearRef, hd] at h
    · simp [footRefs, hd]
  · have : anyDone s = false := by simp [anyDone, List.isEmpty_iff.1 h]
    simp [this, newRef, clearRef]


theorem footRefs_key (s : State) : ∀ r ∈ footRefs s, r.key = 0 := by
  unfold footRefs
  cases anyDone s <;>
    simp only [Bool.false_eq_true, ↓reduceIte, List.cons_append, List.nil_append, List.append_nil,
      List.forall_mem_cons, List.not_mem_nil, false_imp_iff, implies_true, and_true] <;>
    first | exact ⟨rfl, rfl, rfl⟩ | exact ⟨rfl, rfl, rfl, rfl⟩

/-- Only row controls (^204–^207) carry a key; every other control in the view has key 0. -/
theorem view_key (s : State) (ui : UI) :
    ∀ r, InView s ui r → (204 ≤ r.claim ∧ r.claim ≤ 207) ∨ r.key = 0 := by
  intro r hr
  rw [InView, view_refs] at hr
  split at hr
  · simp only [List.mem_cons, List.not_mem_nil, or_false] at hr; subst hr; exact .inr rfl
  · simp only [List.mem_cons, List.mem_append] at hr
    rcases hr with rfl | rfl | hr | hr
    · exact .inr rfl
    · exact .inr rfl
    · obtain ⟨t, -, hr⟩ := List.mem_flatMap.1 hr
      exact .inl (rowRefs_claim s t r hr)
    · exact .inr (footRefs_key s r hr)

/-- A move's controls carry a key when it is a row move (^204–^207). -/
def RowClaim (c : Nat) : Prop := 204 ≤ c ∧ c ≤ 207

/-- **Presence**, for every move of the machine: the control tagged with move `m` and key `k`
is in the view exactly when `m` is enabled at `k` (and `k` is 0 for a move whose controls
carry no key). -/
theorem presence (s : State) (ui : UI) (m : Move State) (hm : m ∈ machine.moves) (k : Nat) :
    InView s ui ⟨m.id, k⟩ ↔ m.enabled s k = true ∧ (RowClaim m.id ∨ k = 0) := by
  have unk : ∀ (c : Nat) (b : Bool), ¬ RowClaim c → (InView s ui ⟨c, 0⟩ ↔ b = true) →
      (InView s ui ⟨c, k⟩ ↔ b = true ∧ (RowClaim c ∨ k = 0)) := by
    intro c b hc h
    simp only [hc, false_or]
    constructor
    · intro h'
      rcases view_key s ui _ h' with h'' | h''
      · exact absurd h'' hc
      · subst h''; exact ⟨h.1 h', rfl⟩
    · rintro ⟨hb, rfl⟩; exact h.2 hb
  have row : ∀ (c : Nat) (b : Bool), RowClaim c → (InView s ui ⟨c, k⟩ ↔ b = true) →
      (InView s ui ⟨c, k⟩ ↔ b = true ∧ (RowClaim c ∨ k = 0)) := by
    intro c b hc h; simp only [hc, true_or, and_true]; exact h
  have nr : ¬ RowClaim 202 ∧ ¬ RowClaim 203 ∧ ¬ RowClaim 208 ∧ ¬ RowClaim 209 ∧ ¬ RowClaim 210 ∧
      ¬ RowClaim 211 := by simp only [RowClaim]; omega
  have rc : RowClaim 204 ∧ RowClaim 205 ∧ RowClaim 206 ∧ RowClaim 207 := by
    simp only [RowClaim]; omega
  simp only [machine, List.mem_cons, List.not_mem_nil, or_false] at hm
  rcases hm with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · refine unk 202 true nr.1 ⟨fun _ => rfl, fun _ => ?_⟩
    rw [InView, view_refs]; split <;> simp [newRef]
  · exact unk 203 _ nr.2.1 (header_present s ui 203 (by omega))
  · exact row 204 _ rc.1 (rowMove_present s ui 204 k (by omega))
  · exact row 205 _ rc.2.1 (rowMove_present s ui 205 k (by omega))
  · exact row 206 _ rc.2.2.1 (rowMove_present s ui 206 k (by omega))
  · exact row 207 _ rc.2.2.2 (edit_present s ui k)
  · exact unk 208 _ nr.2.2.1 (header_present s ui 208 (by omega))
  · exact unk 209 _ nr.2.2.2.1 (header_present s ui 209 (by omega))
  · exact unk 210 _ nr.2.2.2.2.1 (header_present s ui 210 (by omega))
  · exact unk 211 _ nr.2.2.2.2.2 (clear_present s ui)


/-! ## The view fits

Two shapes of `FitsIn.line` cover every box in the view: a row whose children all fill its
height, and a column whose children all fill its width. -/

theorem padOk_zero : PadOk {} := ⟨by decide, by decide, by decide, by decide⟩

theorem fitsIn_row {st : Style} {kids : List Node} {w h : Int} (hax : st.axis = .row)
    (hp : st.padding = {}) (hw : 0 ≤ w) (hh : 0 ≤ h)
    (hk : ∀ k ∈ kids, (nodeSizings k).1.isHug = false ∧ (nodeSizings k).2 = .fill)
    (hb : lineBase true st.gap kids ≤ w)
    (hf : ∀ k ∈ kids, ∀ len : Int,
      ((nodeSizings k).1 = .fill → (w - lineBase true st.gap kids) / ((lineFills true kids : Nat) : Int) ≤ len) →
      (∀ n : Nat, (nodeSizings k).1 = .fixed n → len = n) → FitsIn k len h) :
    FitsIn (.box st none kids) w h := by
  have hc : contentW st w = w := by simp [contentW, hp]
  have hc' : contentH st h = h := by simp [contentH, hp]
  refine .line (by rw [hax]; decide) (by rw [hp]; exact ⟨by decide, by decide, by decide, by decide⟩) (by omega) (by omega) (by simp) ?_ ?_ ?_
  · simpa [hax, Axis.horiz, mainIn, hc] using hb
  · intro k hk'
    obtain ⟨h1, h2⟩ := hk k hk'
    simp [hax, Axis.horiz, crossSz, crossIn, hc', h1, h2, fixedOf, hh]; rfl
  · intro k hk' len hl hn
    obtain ⟨-, h2⟩ := hk k hk'
    have := hf k hk' len (by simpa [hax, Axis.horiz, mainSz, mainIn, hc] using hl)
      (by simpa [hax, Axis.horiz, mainSz] using hn)
    simpa [hax, Axis.horiz, wOf, hOf, crossSz, h2, lenIn, crossIn, hc'] using this

theorem fitsIn_col {st : Style} {kids : List Node} {w h : Int} (hax : st.axis = .column)
    (hp : PadOk st.padding) (hw : 0 ≤ contentW st w) (hh : 0 ≤ contentH st h)
    (hk : ∀ k ∈ kids, (nodeSizings k).2.isHug = false ∧ (nodeSizings k).1 = .fill)
    (hb : lineBase false st.gap kids ≤ contentH st h)
    (hf : ∀ k ∈ kids, ∀ len : Int,
      ((nodeSizings k).2 = .fill →
        (contentH st h - lineBase false st.gap kids) / ((lineFills false kids : Nat) : Int) ≤ len) →
      (∀ n : Nat, (nodeSizings k).2 = .fixed n → len = n) → FitsIn k (contentW st w) len) :
    FitsIn (.box st none kids) w h := by
  refine .line (by rw [hax]; decide) hp hw hh (by simp) ?_ ?_ ?_
  · simpa [hax, Axis.horiz, mainIn] using hb
  · intro k hk'
    obtain ⟨h1, h2⟩ := hk k hk'
    simp [hax, Axis.horiz, crossSz, crossIn, h1, h2, fixedOf, hw]; rfl
  · intro k hk' len hl hn
    obtain ⟨-, h2⟩ := hk k hk'
    have := hf k hk' len (by simpa [hax, Axis.horiz, mainSz, mainIn] using hl)
      (by simpa [hax, Axis.horiz, mainSz] using hn)
    simpa [hax, Axis.horiz, wOf, hOf, crossSz, h2, lenIn, crossIn] using this


theorem cell_fitsIn {w : Sizing} {ctl : Option Control} {kids : List Node} {bgc : Option Color}
    {border : Option Border} {justify : Align} {padding : Insets} {a b : Int}
    (hk : ∀ k ∈ kids, k.isText = true) (hc : ctl.isSome = true → 0 < a ∧ 0 < b) :
    FitsIn (cell w ctl kids bgc border justify padding) a b :=
  .clipped rfl hk hc

/-- A row: checkbox and delete (fixed) around the title (fill), or the edit field after a
spacer. Any width above the two fixed boxes. -/
theorem todoRow_fitsIn (s : State) (ui : UI) (t : Todo) {W : Int} (hW : 2 * (boxW : Int) < W) :
    FitsIn (todoRow s ui t) W rowH := by
  have view : FitsIn (todoRow.viewRow ui t) W rowH := by
    refine fitsIn_row rfl rfl (by omega) (by decide) ?_ ?_ ?_
    · simp only [List.mem_cons, List.not_mem_nil, or_false]
      rintro k (rfl | rfl | rfl) <;> exact ⟨rfl, rfl⟩
    · simp [lineBase, mainSz, nodeSizings, cell, fixedOf, gaps, boxW] at hW ⊢
      omega
    · simp only [List.mem_cons, List.not_mem_nil, or_false]
      rintro k (rfl | rfl | rfl) len hl hn
      · have := hn _ rfl
        exact cell_fitsIn (by simp [Node.isText]) fun _ => by simp [boxW, rowH] at this ⊢; omega
      · have := hl rfl
        simp [lineBase, mainSz, nodeSizings, cell, fixedOf, gaps, boxW, lineFills, Sizing.isFill] at this hW
        exact cell_fitsIn (by simp [Node.isText]) fun _ => ⟨by omega, by decide⟩
      · have := hn _ rfl
        exact cell_fitsIn (by cases hot ui t.id <;> simp [Node.isText])
          fun _ => by simp [boxW, rowH] at this ⊢; omega
  unfold todoRow
  split
  · split
    · refine fitsIn_row rfl rfl (by omega) (by decide) ?_ ?_ ?_
      · simp only [List.mem_cons, List.not_mem_nil, or_false]
        rintro k (rfl | rfl) <;> exact ⟨rfl, rfl⟩
      · simp [lineBase, mainSz, nodeSizings, spacer, cell, fixedOf, gaps, boxW] at hW ⊢
        omega
      · simp only [List.mem_cons, List.not_mem_nil, or_false]
        rintro k (rfl | rfl) len hl hn
        · exact cell_fitsIn (by simp) (by simp)
        · have := hl rfl
          simp [lineBase, mainSz, nodeSizings, spacer, cell, fixedOf, gaps, boxW, lineFills,
            Sizing.isFill] at this hW
          exact .field (by omega) (by decide)
    · exact view
  · exact view


theorem todoRow_sizings (s : State) (ui : UI) (t : Todo) :
    nodeSizings (todoRow s ui t) = (.fill, .fixed rowH) := by
  unfold todoRow; split
  · split <;> rfl
  · rfl

theorem lineBase_rows (s : State) (ui : UI) :
    ∀ ts : List Todo, lineBase false 0 (ts.map (todoRow s ui)) = (rowH : Int) * ts.length
  | [] => by simp [lineBase, gaps]
  | t :: ts => by
    have := lineBase_rows s ui ts
    simp only [lineBase, gaps, Nat.zero_mul, Int.natCast_zero, Int.add_zero, List.map_cons,
      List.sum_cons, List.length_cons] at this ⊢
    rw [this]
    simp only [mainSz, todoRow_sizings, Bool.false_eq_true, ↓reduceIte, fixedOf]
    push_cast; rw [Int.mul_add, Int.mul_one, Int.add_comm]

/-- The list: one row per listed todo, stacked, exactly as tall as its rows. -/
theorem list_fitsIn (s : State) (ui : UI) {W : Int} (hW : 2 * (boxW : Int) < W) :
    FitsIn (list s ui) W ((rowH * (visible s).length : Nat) : Int) := by
  refine fitsIn_col rfl padOk_zero ?_ ?_ ?_ ?_ ?_
  · simp only [contentW]; omega
  · simp only [contentH]; omega
  · intro k hk
    obtain ⟨t, -, rfl⟩ := List.mem_map.1 hk
    rw [todoRow_sizings]; exact ⟨rfl, rfl⟩
  · simp only [lineBase_rows, contentH]; push_cast; omega
  · intro k hk len _ hn
    obtain ⟨t, -, rfl⟩ := List.mem_map.1 hk
    have := hn rowH (todoRow_sizings s ui t ▸ rfl)
    subst this
    exact todoRow_fitsIn s ui t (by simp only [contentW]; omega)


/-- The header: toggle all (or a spacer) and the new-todo field, which fills the rest. -/
theorem header_fitsIn (s : State) (ui : UI) {W : Int} (hW : (boxW : Int) < W) :
    FitsIn (header s ui) W headerH := by
  have first : ∀ k, k = (if s.todos.isEmpty then spacer boxW else
      cell (.fixed boxW)
        (some { ref := toggleAllRef, role := .checkbox, label := "Mark all as complete",
                checked := some (allDone s) })
        [.text { font := body, color := if allDone s then ink else faint } "❯"]
        (border := ring ui toggleAllRef)) →
      nodeSizings k = (.fixed boxW, .fill) ∧ ∀ a b : Int, 0 < a → 0 < b → FitsIn k a b := by
    rintro k rfl
    split
    · exact ⟨rfl, fun _ _ _ _ => cell_fitsIn (by simp) (by simp)⟩
    · exact ⟨rfl, fun _ _ ha hb => cell_fitsIn (by simp [Node.isText]) fun _ => ⟨ha, hb⟩⟩
  unfold header
  generalize hx : (if s.todos.isEmpty = true then spacer boxW else _) = x
  obtain ⟨h1, h2⟩ := first x hx.symm
  refine fitsIn_row rfl rfl (by omega) (by decide) ?_ ?_ ?_
  · simp only [List.mem_cons, List.not_mem_nil, or_false]
    rintro k (rfl | rfl)
    · rw [h1]; exact ⟨rfl, rfl⟩
    · exact ⟨rfl, rfl⟩
  · simp only [lineBase, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil, mainSz, h1]
    simp only [↓reduceIte, fixedOf, nodeSizings, gaps]
    simp [boxW] at hW ⊢; omega
  · simp only [List.mem_cons, List.not_mem_nil, or_false]
    rintro k (rfl | rfl) len hl hn
    · have := hn boxW (by rw [h1])
      exact h2 _ _ (by simp [boxW] at this; omega) (by decide)
    · have := hl rfl
      simp only [lineBase, lineFills, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil,
        mainSz, h1, List.filter_cons] at this
      simp only [↓reduceIte, fixedOf, nodeSizings, gaps, Sizing.isFill, List.filter_nil] at this
      simp [boxW] at this hW
      exact .field (by omega) (by decide)

/-- The footer: the counter (fill), three filters and Clear completed (or a spacer). -/
theorem footer_fitsIn (s : State) (ui : UI) {W : Int} (hW : 3 * (filterW : Int) + clearW < W) :
    FitsIn (footer s ui) W footH := by
  have last : ∀ k, k = (if anyDone s then
        cell (.fixed clearW) (some { ref := clearRef, label := "Clear completed" })
          [.text { font := small, color := ink } "Clear completed"]
          (border := ring ui clearRef)
      else spacer clearW) →
      nodeSizings k = (.fixed clearW, .fill) ∧ ∀ a b : Int, 0 < a → 0 < b → FitsIn k a b := by
    rintro k rfl
    split
    · exact ⟨rfl, fun _ _ ha hb => cell_fitsIn (by simp [Node.isText]) fun _ => ⟨ha, hb⟩⟩
    · exact ⟨rfl, fun _ _ _ _ => cell_fitsIn (by simp) (by simp)⟩
  have fb : ∀ f, nodeSizings (filterBox s ui f) = (.fixed filterW, .fill) ∧
      ∀ a b : Int, 0 < a → 0 < b → FitsIn (filterBox s ui f) a b :=
    fun _ => ⟨rfl, fun _ _ ha hb => cell_fitsIn (by simp [Node.isText]) fun _ => ⟨ha, hb⟩⟩
  unfold footer
  generalize hx : (if anyDone s = true then _ else spacer clearW) = x
  obtain ⟨h1, h2⟩ := last x hx.symm
  refine fitsIn_row rfl rfl (by omega) (by decide) ?_ ?_ ?_
  · simp only [List.mem_cons, List.not_mem_nil, or_false]
    rintro k (rfl | rfl | rfl | rfl | rfl)
    · exact ⟨rfl, rfl⟩
    all_goals first | (rw [(fb _).1]; exact ⟨rfl, rfl⟩) | (rw [h1]; exact ⟨rfl, rfl⟩)
  · simp only [lineBase, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil, mainSz, h1,
      (fb _).1]
    simp only [↓reduceIte, fixedOf, nodeSizings, gaps, cell]
    simp [filterW, clearW] at hW ⊢; omega
  · simp only [List.mem_cons, List.not_mem_nil, or_false]
    rintro k (rfl | rfl | rfl | rfl | rfl) len hl hn
    · exact cell_fitsIn (by simp [Node.isText]) (by simp)
    all_goals first
      | (have := hn filterW (by rw [(fb _).1]); exact (fb _).2 _ _ (by simp [filterW] at this; omega) (by decide))
      | (have := hn clearW (by rw [h1]); exact h2 _ _ (by simp [clearW] at this; omega) (by decide))

theorem heading_fitsIn {a b : Int} : FitsIn heading a b := .clipped rfl (by simp [Node.isText]) (by simp)
theorem info_fitsIn {a b : Int} : FitsIn info a b := .clipped rfl (by simp [Node.isText]) (by simp)


/-- **The view fits** every window at least `minWidth` wide and `height s` tall, in every state
and under any interaction state. -/
theorem view_fitsIn (s : State) (ui : UI) {w h : Int} (hw : (minWidth : Int) ≤ w)
    (hh : (height s : Int) ≤ h) : FitsIn (view s ui) w h := by
  have hW : 3 * (filterW : Int) + clearW < w - pad - pad := by
    simp only [minWidth, pad, filterW, clearW] at hw ⊢; omega
  unfold view
  refine fitsIn_col rfl ⟨by decide, by decide, by decide, by decide⟩ ?_ ?_ ?_ ?_ ?_
  · simp only [contentW, pad] at hW ⊢; omega
  · simp only [contentH, height, pad] at hh ⊢; split at hh <;> omega
  · cases s.todos.isEmpty <;>
      simp only [Bool.false_eq_true, ↓reduceIte, List.cons_append, List.nil_append,
        List.mem_cons, List.not_mem_nil, or_false] <;>
      rintro k (rfl | rfl | rfl | rfl | rfl) <;> exact ⟨rfl, rfl⟩
  · cases he : s.todos.isEmpty <;>
      simp only [height, he, Bool.false_eq_true, ↓reduceIte] at hh <;>
      simp [contentH, pad, headH, headerH, rowH, footH, infoH, lineBase, mainSz, nodeSizings,
        heading, header, list, footer, info, fixedOf, gaps] at hh ⊢ <;> omega
  · cases s.todos.isEmpty <;>
      simp only [Bool.false_eq_true, ↓reduceIte, List.cons_append, List.nil_append,
        List.mem_cons, List.not_mem_nil, or_false] <;>
      rintro k (rfl | rfl | rfl | rfl | rfl) len _ hn
    · exact heading_fitsIn
    · have := hn _ rfl; subst this
      exact header_fitsIn s ui (by simp only [contentW, filterW, clearW, boxW] at hW ⊢; omega)
    · have := hn _ rfl; subst this
      exact list_fitsIn s ui (by simp only [contentW, filterW, clearW, boxW] at hW ⊢; omega)
    · have := hn _ rfl; subst this
      exact footer_fitsIn s ui (by simp only [contentW] at hW ⊢; omega)
    · exact info_fitsIn
    · exact heading_fitsIn
    · have := hn _ rfl; subst this
      exact header_fitsIn s ui (by simp only [contentW, filterW, clearW, boxW] at hW ⊢; omega)
    · exact info_fitsIn


/-! ## Pressable -/

/-- **Every control is pressable at its centre**, in every state, with any text metrics, in
any window at least `minWidth` wide and `height s` tall: hit testing there returns it. -/
theorem view_pressable (s : State) (ui : UI) (m : TextMetrics) (w : Size)
    (hw : (minWidth : Int) ≤ w.w) (hh : (height s : Int) ≤ w.h) :
    ∀ t ∈ targets (layout m w (view s ui)),
      hitTest (layout m w (view s ui)) t.visible.center = some t.control := by
  have hf := view_fitsIn s ui (w := max 0 w.w) (h := max 0 w.h) (by omega) (by omega)
  unfold view at hf ⊢
  exact hitTest_center_of_fitsIn rfl rfl hf

/-- **Pressable, per move** (M1, docs/goals/m1.md): for every move of the machine enabled at key `k`, its
control is on screen, and hit testing at the control's centre returns that control, in any
window at least `minWidth` × `height s`, with any metrics. -/
theorem enabled_pressable (s : State) (ui : UI) (m : TextMetrics) (w : Size)
    (hw : (minWidth : Int) ≤ w.w) (hh : (height s : Int) ≤ w.h)
    (mv : Move State) (hm : mv ∈ machine.moves) (k : Nat) (he : mv.enabled s k = true)
    (hk : RowClaim mv.id ∨ k = 0) :
    ∃ t ∈ targets (layout m w (view s ui)), t.ref = ⟨mv.id, k⟩ ∧
      hitTest (layout m w (view s ui)) t.visible.center = some t.control := by
  have hin := (presence s ui mv hm k).2 ⟨he, hk⟩
  rw [InView, ← layout_controls m w, ← targetsOf_controls, List.map_map] at hin
  obtain ⟨t, ht, e⟩ := List.mem_map.1 hin
  exact ⟨t, ht, e, view_pressable s ui m w hw hh t ht⟩

/-! ## Presence in the frame and on screen -/

/-- **Presence in the frame**: in the accessibility tree of the frame, for any metrics and
window size, move `mv`'s control with key `k` is there exactly when `mv` is enabled at `k`. -/
theorem presence_in_frame (s : State) (ui ui' : UI) (m : TextMetrics) (w : Size)
    (mv : Move State) (hm : mv ∈ machine.moves) (k : Nat) :
    (⟨mv.id, k⟩ : ControlRef) ∈
        (Frame.ofLaid ui' (layout m w (view s ui))).ax.toList.filterMap AxNode.control ↔
      mv.enabled s k = true ∧ (RowClaim mv.id ∨ k = 0) := by
  rw [Frame.controls_ofLaid_layout]; exact presence s ui mv hm k

/-- …and in every frame the running app shows (the runtime lays out `view` with the config's
layout, which is `layout` unless a test swaps it). -/
theorem presence_on_screen (cfg : Config) (h : cfg.layout = layout) (st : Runtime.State State)
    (ui : UI) (hl : st.laid = relayout app cfg st.app ui) (mv : Move State)
    (hm : mv ∈ machine.moves) (k : Nat) :
    (⟨mv.id, k⟩ : ControlRef) ∈ (Frame.ofLaid st.ui st.laid).ax.toList.filterMap AxNode.control ↔
      mv.enabled st.app k = true ∧ (RowClaim mv.id ∨ k = 0) := by
  rw [hl, relayout, h]; exact presence_in_frame st.app ui st.ui cfg.metrics ui.size mv hm k


/-! ## Every reachable state -/

theorem Ascending.nodup : ∀ {lo : Nat} {xs : List Todo}, Ascending lo xs → (xs.map (·.id)).Nodup
  | _, [], _ => List.nodup_nil
  | _, x :: xs, ⟨_, h2⟩ => by
    refine List.nodup_cons.2 ⟨fun hx => ?_, Ascending.nodup h2⟩
    obtain ⟨j, hj, e⟩ := List.mem_map.1 hx
    have := Ascending.lt h2 j hj
    simp only at e
    omega

/-- **The M1 invariants**, in every state the machine reaches: the counter is the number of
active todos, todo ids are distinct, and the rows on screen are the filter applied to the todos,
in order. -/
theorem reachable_invariants {s : State} (h : machine.Reachable s) :
    s.left = active s.todos ∧ (s.todos.map (·.id)).Nodup ∧
      ∀ ui, (view s ui).controls.filterMap rowKey = (visible s).map (·.id) := by
  obtain ⟨h1, h2, -, -⟩ := counterAndIds.reachable s h
  exact ⟨h1, Ascending.nodup h2, listedRows.reachable s h⟩

/-- …in every state the running app reaches, whatever events arrive. -/
theorem invariants_on_screen (cfg : Config) (size : Size) (scale : Nat) (es : List Event) :
    let st := (steps app cfg (start app cfg size scale) es).1.app
    st.left = active st.todos ∧ (st.todos.map (·.id)).Nodup ∧
      ∀ ui, (view st ui).controls.filterMap rowKey = (visible st).map (·.id) :=
  reachable_invariants (steps_reachable machine view claimInfos cfg size scale es (some newRef))

end Examples.Todo
