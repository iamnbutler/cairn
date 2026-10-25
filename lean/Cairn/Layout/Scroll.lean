import Cairn.Layout.Proofs
import Cairn.Layout.Bridge

/-! # Scroll boxes: what holds of every one

The framework's facts about scroll boxes (`Style.scroll`, docs/layout.md, "Scroll boxes"), for
any scroll box, any children, any text metrics and any window:

* `scroll_rects`, `scroll_column_rects`: the children are where the same box without scrolling
  puts them, moved back by the offset (in a column: same `x`, width and height, `y` less the
  offset).
* `layout_scrollApart`: in a row or column scroll box, the children's rects don't overlap, and
  what shows of anything under the box is inside the box.
* `pressed_where_visible`: in a `Pressable` view, a control with a visible part is hit at that
  part's centre, and a control with none is hit nowhere.

The test fixture states them for its own scroll box as claims (`fixture^11`–`^13`,
test/fixture/lean/Checks/Scroll.lean). -/

namespace Cairn.Layout
open Cairn Cairn.Runtime

/-- **Children at the unscrolled place, moved back.** Laid out anywhere, a scroll box with offset
`o` puts each child at the rect the same box without `scroll` gives it, moved back by `o` along
its axis (`Rect.scrollBy`: left in a row, up otherwise). -/
theorem scroll_rects (m : TextMetrics) (c r : Rect) (aw : Int) (st : Style)
    (ctl : Option Control) (kids : List Node) (o : Int) :
    (arrange m c r (measure m aw (.box { st with scroll := some o } ctl kids))).children.map
        Laid.rect =
      ((arrange m c r (measure m aw (.box { st with scroll := none } ctl kids))).children.map
        Laid.rect).map (Rect.scrollBy (Axis.horiz st.axis) o) := by
  rw [measure_scroll, measure_scroll, arrange_scroll _ _ _ _ _ _ rfl]
  rfl

/-- **In a column, `y` less the offset.** A column scroll box with offset `o` puts each child
where the same column without scrolling does, `o` points higher: same `x`, width and height. -/
theorem scroll_column_rects (m : TextMetrics) (c r : Rect) (aw : Int) (st : Style)
    (ctl : Option Control) (kids : List Node) (o : Int) (hcol : st.axis = .column) :
    (arrange m c r (measure m aw (.box { st with scroll := some o } ctl kids))).children.map
        Laid.rect =
      ((arrange m c r (measure m aw (.box { st with scroll := none } ctl kids))).children.map
        Laid.rect).map fun q => ⟨q.x, q.y - o, q.w, q.h⟩ := by
  rw [scroll_rects]
  simp only [hcol, Axis.horiz]
  rfl

/-- At a row or column scroll box: its children's rects are pairwise disjoint, and every node
under it shows only inside it (each nonempty visible part, `rect ∩ clip`, is inside the box). -/
def ScrollApart : Laid → Prop
  | .box r _ st _ kids => st.scroll.isSome = true → st.axis ≠ .stack →
      kids.Pairwise (fun a b => a.rect.disjoint b.rect) ∧
      ∀ k ∈ kids, k.Everywhere fun d => d.visible.nonempty → d.visible.inside r
  | _ => True

/-- **Apart, and inside the box.** Every row or column scroll box in every laid-out view keeps
its children apart and shows them only inside itself. -/
theorem layout_scrollApart (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).Everywhere ScrollApart :=
  ((layout_siblingsDisjoint m w n).and (layout_clipContained m w n)).imp fun l h => by
    cases l with
    | box r ctl st info kids =>
      intro hs hax
      have hc : st.clips = true := by simp only [Style.clips, hs, Bool.or_true]
      exact ⟨h.1 hax, h.2 hc⟩
    | _ => trivial

/-- **Pressed where it shows, and nowhere else.** In a `Pressable` view, a control with a
nonempty visible part is hit at that part's centre, and a control scrolled wholly out of view
(an empty visible part) is the hit at no point. -/
theorem pressed_where_visible {m : TextMetrics} {w : Size} {n : Node}
    (hp : Pressable w (layout m w n)) {t : Target} (ht : t ∈ targets (layout m w n)) :
    (t.visible.nonempty → hitTest (layout m w n) t.visible.center = some t.control) ∧
    (¬ t.visible.nonempty → ∀ p, hitTarget (layout m w n) p ≠ some t) :=
  ⟨hitTest_center_of_pressable hp ht, fun h p => not_hit_of_hidden hp h p⟩

end Cairn.Layout
