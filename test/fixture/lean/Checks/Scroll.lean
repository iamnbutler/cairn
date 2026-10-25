import Fixture
import Cairn.Layout

/-! # The fixture's list: claims ^12, ^13, ^19 and ^20 (^11 and ^15 retired)

Cairn's scroll-box and virtual-list theorems (`Cairn.Layout.Scroll`, `Cairn.UI.VList`,
`Cairn.Layout.VList`), stated for the fixture's virtual list at the offset the runtime gives it,
in every state, for any text metrics, any `UI` and any window. In their own file because the
layout proofs aren't in a `module`, and `Fixture` is one (the host links it). -/

namespace Fixture.Scroll
open Cairn Cairn.Claims Cairn.Layout Cairn.Runtime Fixture

/-- The list in a laid-out fixture view: the root's eighth and last child. -/
def rowsOf (l : Laid) : Laid := l.children.getD 7 default

/-- The view's scroll box is `rowsBox`, measured and arranged somewhere in the window. -/
theorem rowsOf_layout (m : TextMetrics) (w : Size) (s : State) (ui : UI) :
    ∃ c r aw, rowsOf (layout m w (view s ui)) =
      arrange m c r (Layout.measure m aw (rowsBox s ui)) :=
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
/-- ^19's statement: the list's children (the spacer for the rows above, the rows laid, the
spacer below) are one under the other from the top of its content box less the runtime's offset
(`vlist_stacked`): no gaps, no overlaps, whatever height each row turns out to be. -/
def RowsStacked (s : State) : Prop :=
  ∀ (m : TextMetrics) (ui : UI) (w : Size), ∃ (c r : Rect) (aw : Int) (st : Style),
    rowsOf (layout m w (view s ui)) = arrange m c r (Layout.measure m aw (rowsBox s ui)) ∧
    Stacked ((rowsOf (layout m w (view s ui))).children.map Laid.rect)
      ((r.inset st.padding).y - ui.scrollOf rowsRef)

theorem rowsStacked (s : State) : RowsStacked s := by
  intro m ui w
  obtain ⟨c, r, aw, h⟩ := rowsOf_layout m w s ui
  obtain ⟨st, -, -, -, hs⟩ := vlist_stacked m c r aw rowsList ui s.keys (rowOf s ui)
  exact ⟨c, r, aw, st, h, h ▸ hs⟩

/-- ^20's statement: the list builds row `i` exactly when the row's extent, in the heights it
lays out by, meets the box widened by the overscan above and below; and it builds no more than
`(viewport + 2·overscan) / minHeight + 2` rows, however many the list has (`node_rows`). -/
def RowsWindowed (s : State) : Prop :=
  ∀ ui : UI,
    let info := VList.infoOf rowsList ui s.keys
    (∀ i, i < s.keys.size → (info.first ≤ i ∧ i < info.last ↔
        ui.scrollOf rowsRef - rowsList.overscan < info.modelOf.top i + info.modelOf.height i ∧
        info.modelOf.top i < ui.scrollOf rowsRef + info.viewport + rowsList.overscan)) ∧
    0 ≤ info.viewport ∧
    (((info.last - info.first : Nat) : Int) ≤
      (info.viewport + 2 * rowsList.overscan) / info.modelOf.minHeight + 2)

theorem rowsWindowed (s : State) : RowsWindowed s :=
  fun ui => VList.node_rows rowsList ui s.keys

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
  obtain ⟨st, hs, hcol, -, -, -, -, hn⟩ := VList.node_eq rowsList ui s.keys (rowOf s ui)
  simp only [rowsBox, hn, Layout.measure, arrange, ScrollApart, Laid.children, Laid.rect] at hE ⊢
  obtain ⟨hd, hc⟩ := hE (by simp only [hs, Option.isSome_some]) (by rw [hcol]; decide)
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

retire ^15 invariant "Rows are the column, moved up by the runtime's offset" because "The rows are a virtual list now (#204): the box builds only the rows near the offset, so its children aren't the whole column. ^19 states where the rows built are, ^20 which are built."

invariant ^19 rowsStackedInvariant "Rows are one under the other from the offset" for machine where
  does "The rows the list builds, and the spacers for the rows above and below them, are one under the other from the top of the box less the offset the runtime keeps for it (^14): no gaps, no overlaps, whatever height each row turns out to be. Any metrics, any window, any offset, every state."
  holds s := RowsStacked s
  init := rowsStacked _
  step := fun _ _ _ => rowsStacked _
  receive := fun _ _ _ => rowsStacked _

invariant ^20 rowsWindowedInvariant "Only the rows near the view are built" for machine where
  does "The list builds a row exactly when it meets the box widened by 200 points above and below, in the heights the runtime has recorded (the mean of them for rows not yet laid), and never more rows than the box and that margin can hold at the shortest row's height, however long the list. Any window, any offset, every state."
  holds s := RowsWindowed s
  init := rowsWindowed _
  step := fun _ _ _ => rowsWindowed _
  receive := fun _ _ _ => rowsWindowed _

invariant ^12 rowsApartInvariant "Rows stay apart, and what shows is inside the box" for machine where
  does "The rows of the list never overlap, and every part of a row that shows is inside the box. Any metrics, any window, every state."
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
