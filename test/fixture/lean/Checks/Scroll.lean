import Fixture
import Cairn.Layout

/-! # The fixture's scroll box: claims ^12, ^13 and ^15 (^11 retired)

Cairn's scroll-box theorems (`Cairn.Layout.Scroll`), stated for the fixture's box of 200 rows at
the offset the runtime gives it, in every state, for any text metrics, any `UI` and any window. In their own file because the
layout proofs aren't in a `module`, and `Fixture` is one (the host links it). -/

namespace Fixture.Scroll
open Cairn Cairn.Claims Cairn.Layout Cairn.Runtime Fixture

/-- The scroll box in a laid-out fixture view: the root's eighth and last child. -/
def rowsOf (l : Laid) : Laid := l.children.getD 7 default

/-- The view's scroll box is `rowsBox`, measured and arranged somewhere in the window. -/
theorem rowsOf_layout (m : TextMetrics) (w : Size) (s : State) (ui : UI) :
    ∃ c r aw, rowsOf (layout m w (view s ui)) =
      arrange m c r (Layout.measure m aw (rowsBox (some (ui.scrollOf rowsRef)) s ui)) :=
  ⟨_, _, _, rfl⟩

theorem rowsOf_mem (m : TextMetrics) (w : Size) (s : State) (ui : UI) :
    rowsOf (layout m w (view s ui)) ∈ (layout m w (view s ui)).children := by
  have hl : (layout m w (view s ui)).children.length = 8 := by
    simp only [layout, view, Layout.measure, arrange_children_box, arrangeList_length, measureList,
      List.length_cons, List.length_nil]
  unfold rowsOf
  rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (by omega), Option.getD_some]
  exact List.getElem_mem _

-- region: fixture-scroll-claims
/-- ^15's statement: every row is where the same column, not scrolling, puts it, the runtime's
offset higher (`scroll_column_rects`). -/
def RowsShifted (s : State) : Prop :=
  ∀ (m : TextMetrics) (ui : UI) (w : Size), ∃ c r aw,
    rowsOf (layout m w (view s ui)) = arrange m c r (Layout.measure m aw (rowsBox (some (ui.scrollOf rowsRef)) s ui)) ∧
    (rowsOf (layout m w (view s ui))).children.map Laid.rect =
      ((arrange m c r (Layout.measure m aw (rowsBox none s ui))).children.map Laid.rect).map
        fun q => ⟨q.x, q.y - ui.scrollOf rowsRef, q.w, q.h⟩

theorem rowsShifted (s : State) : RowsShifted s := by
  intro m ui w
  obtain ⟨c, r, aw, h⟩ := rowsOf_layout m w s ui
  exact ⟨c, r, aw, h, h ▸ scroll_column_rects m c r aw
    ({ width := .fill, height := .fixed rowsH, scrollRef := some rowsRef } : Style) none (rows s ui)
    (ui.scrollOf rowsRef) rfl⟩

/-- ^12's statement: the rows don't overlap, and what shows of each is inside the box
(`layout_scrollApart`). -/
def RowsApart (s : State) : Prop :=
  ∀ (m : TextMetrics) (ui : UI) (w : Size),
    (rowsOf (layout m w (view s ui))).children.Pairwise (fun a b => a.rect.disjoint b.rect) ∧
    ∀ k ∈ (rowsOf (layout m w (view s ui))).children, k.visible.nonempty →
      k.visible.inside (rowsOf (layout m w (view s ui))).rect

theorem rowsApart (s : State) : RowsApart s := by
  intro m ui w
  have hE := ((layout_scrollApart m w (view s ui)).child (rowsOf_mem m w s ui)).here
  obtain ⟨c, r, aw, h⟩ := rowsOf_layout m w s ui
  rw [h] at hE ⊢
  simp only [rowsBox, Layout.measure, arrange, ScrollApart, Laid.children, Laid.rect] at hE ⊢
  obtain ⟨hd, hc⟩ := hE rfl (by decide)
  exact ⟨hd, fun k hk hne => (hc k hk).here hne⟩

/-- ^13's statement: wherever the view is `Pressable` (the fuzzer checks it at every step), a
control with a visible part is hit at that part's centre, and one scrolled wholly out of view
is hit nowhere (`pressed_where_visible`). -/
def PressedWhereVisible (s : State) : Prop :=
  ∀ (m : TextMetrics) (ui : UI) (w : Size), Pressable w (layout m w (view s ui)) →
    ∀ t ∈ targets (layout m w (view s ui)),
      (t.visible.nonempty → hitTest (layout m w (view s ui)) t.visible.center = some t.control) ∧
      (¬ t.visible.nonempty → ∀ p, hitTarget (layout m w (view s ui)) p ≠ some t)

theorem pressedWhereVisible (s : State) : PressedWhereVisible s :=
  fun _ _ _ hp _ ht => pressed_where_visible hp ht

retire ^11 invariant "Rows are the column, moved up by the offset" because "The offset was a constant in the view; the runtime owns it now (#203), so the statement is ^15's, at the runtime's offset."

invariant ^15 rowsScrolledInvariant "Rows are the column, moved up by the runtime's offset" for machine where
  does "Every row of the scroll box, and the end line, is where the same box, not scrolling, puts it, moved up by the offset the runtime keeps for the box (^14): same x, width and height. Any metrics, any window, any offset, every state."
  holds s := RowsShifted s
  init := rowsShifted _
  step := fun _ _ _ => rowsShifted _
  receive := fun _ _ _ => rowsShifted _

invariant ^12 rowsApartInvariant "Rows stay apart, and what shows is inside the box" for machine where
  does "The rows of the scroll box never overlap, and every part of a row that shows is inside the box. Any metrics, any window, every state."
  holds s := RowsApart s
  init := rowsApart _
  step := fun _ _ _ => rowsApart _
  receive := fun _ _ _ => rowsApart _

invariant ^13 pressedWhereVisibleInvariant "Controls are pressed where they show" for machine where
  does "Wherever the view is pressable, a press at the centre of what shows of a control, even a row half scrolled out of view, reaches it, and a row scrolled wholly out is reached nowhere. Any metrics, every state."
  holds s := PressedWhereVisible s
  init := pressedWhereVisible _
  step := fun _ _ _ => pressedWhereVisible _
  receive := fun _ _ _ => pressedWhereVisible _
-- endregion: fixture-scroll-claims

end Fixture.Scroll
