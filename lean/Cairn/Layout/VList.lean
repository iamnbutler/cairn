import Cairn.Layout.Proofs
import Cairn.VList

/-! # Virtual lists: what the layout does with them

`Cairn.VList` proves which rows a virtual list builds and that, in the heights it lays out
by, each row starts where the one before ends (`Model.top_succ`). This file proves the layout's
side: a column with no gap, justified to the start, as every `VList.node` box is (`node_eq`),
lays its children one under the other, each starting where the one before it ends, the first at
the top of its content box less the offset, whatever the children's heights.

* `Stacked`: rects one under the other from `y`, with no gaps and no overlaps.
* `arrange_stacked`: such a box's laid children are `Stacked` from its content top less the
  offset.
* `vlist_stacked`: so are a laid `VList.node`'s: the spacer for the rows above, the rows in key
  order, and the spacer for the rows below. -/

namespace Cairn.Layout
open Cairn

/-- `rs` lie one under the other from `y`: the first starts at `y`, each next one where the one
before it ends. -/
def Stacked : List Rect → Int → Prop
  | [], _ => True
  | r :: rs, y => r.y = y ∧ Stacked rs (r.y + r.h)

theorem Line.go_stacked (ln : Line) (hz : ln.horiz = false) (hs : ∀ i, ln.spacing i = 0) :
    ∀ (items : List Item) (i j : Nat) (pos : Int), Stacked (ln.go i j pos items) pos
  | [], _, _, _ => trivial
  | it :: its, i, j, pos => by
    simp only [Line.go, Stacked, mkRect, hz, Bool.false_eq_true, ↓reduceIte, hs, Int.add_zero]
    exact ⟨trivial, Line.go_stacked ln hz hs its _ _ _⟩

theorem stacked_map (o : Int) : ∀ (rs : List Rect) (y : Int),
    Stacked rs y → Stacked (rs.map fun q => { q with y := q.y - o }) (y - o)
  | [], _, _ => trivial
  | r :: rs, y, ⟨h1, h2⟩ => by
    refine ⟨by simp only [h1], ?_⟩
    have := stacked_map o rs _ h2
    have e : r.y + r.h - o = r.y - o + r.h := by omega
    rw [e] at this; exact this

/-- **One under the other.** A column scroll box with no gap, justified to the start and
scrolled by `o`, lays its children one under the other: the first at the top of its content box
less `o`, each next where the one before it ends. -/
theorem arrange_stacked (m : TextMetrics) (c r : Rect) {st : Style} (ctl : Option Control)
    (sz : Size) (kids : List Sized) {o : Int} (ho : st.scroll = some o)
    (hcol : st.axis = .column) (hgap : st.gap = 0) (hj : st.justify = .start) :
    Stacked ((arrange m c r (.box st ctl sz kids)).children.map Laid.rect)
      ((r.inset st.padding).y - o) := by
  rw [arrange_children_box, arrangeList_rects _ _ _ _ (by simp only [childRects_length, List.length_map])]
  simp only [childRects, scrolled, ho, placeRects, hcol, Axis.horiz]
  refine stacked_map o _ _ ?_
  have := Line.go_stacked (lineOf false st (r.inset st.padding) (kids.map Sized.item)) rfl
    (fun i => by simp only [lineOf, spacing, hj, hgap]; rfl)
    (kids.map Sized.item) 0 0 (r.inset st.padding).y
  simp only [lineRects, Bool.false_eq_true, ↓reduceIte, hj, startOffset, Int.add_zero]
  exact this

/-- **A virtual list's rows, laid.** However tall its rows turn out, a laid `VList.node` puts the
spacer for the rows above, the rows in key order and the spacer below one under the other, from
the top of its content box less the runtime's offset: no gaps, no overlaps. -/
theorem vlist_stacked (m : TextMetrics) (c r : Rect) (aw : Int) (v : VList) (ui : UI)
    (keys : Array Nat) (row : Nat → Node) :
    ∃ st, st.rows = some (VList.infoOf v ui keys) ∧ st.scroll = some (ui.scrollOf v.ref) ∧
      VList.node v ui keys row = .box st none
        (VList.spacer ((VList.infoOf v ui keys).modelOf.top (VList.infoOf v ui keys).first) ::
          VList.rowNodes keys row (VList.infoOf v ui keys).first (VList.infoOf v ui keys).last ++
          [VList.spacer ((VList.infoOf v ui keys).modelOf.top (VList.infoOf v ui keys).modelOf.count -
            (VList.infoOf v ui keys).modelOf.top (VList.infoOf v ui keys).last)]) ∧
      Stacked ((arrange m c r (measure m aw (VList.node v ui keys row))).children.map Laid.rect)
        ((r.inset st.padding).y - ui.scrollOf v.ref) := by
  obtain ⟨st, hs, hcol, hgap, hj, -, hrows, hn⟩ := VList.node_eq v ui keys row
  refine ⟨st, hrows, hs, hn, ?_⟩
  rw [hn]
  simp only [measure]
  exact arrange_stacked m c r none _ _ hs hcol hgap hj

namespace VList_checks
open VList

/-! ## Checks -/

-- 100 rows, nothing known, an estimate of 10: rows 0 to 4 meet [0, 50); 12 to 17 meet [125, 175).
#guard (model (Array.range 100) {} (some 10)).window 0 50 == (0, 5)
#guard (model (Array.range 100) {} (some 10)).window 125 175 == (12, 18)
-- Past the end and before the start, nothing.
#guard (model (Array.range 100) {} (some 10)).window 2000 2100 == (100, 100)
#guard (model (Array.range 100) {} (some 10)).window (-100) 0 == (0, 0)
-- Row 3 known at 50: rows 4 on are 40 lower; row 3 is [30, 80), so [60, 110) meets rows 3 to 6.
def knownAt3 : Known := { count := 100, rows := #[{ index := 3, key := 3, height := 50 }] }
#guard (model (Array.range 100) knownAt3 (some 10)).window 60 110 == (3, 7)
#guard ((model (Array.range 100) knownAt3 (some 10)).topF
  (model (Array.range 100) knownAt3 (some 10)).pre 5) == 90
-- With no estimate given, the mean of the known heights.
#guard (model (Array.range 100) knownAt3 none).est == 50
-- Two rows inserted at the head: row 3's height moves with its key, to index 5.
#guard (align (#[1000, 1001] ++ Array.range 100) knownAt3).toList.map (·.index) == [5]
-- A key that is gone takes its height with it.
#guard (align ((Array.range 100).filter (· != 3)) knownAt3).size == 0


end VList_checks

end Cairn.Layout
