module

public import Cairn.UI.Node

/-! # Grids that follow their box

A `Grid` lays equal cards out in rows, as many columns as fit the box's width. It is plain
arithmetic on the box's size, so a view builds it from the window size the runtime keeps
(`UI.size`, updated by every `resize` event): the host only reports the size and Lean decides
every rect. Resizing the window changes the size, the view runs again and the cards reflow.

* **Columns** are as many cards of `minWidth` as fit with the gaps between them, and at least one
  (`columns`). The cards then share the width equally, so they grow until another column fits.
* **Cards keep their aspect ratio** (`ratioW : ratioH`), plus a fixed `caption` height under it
  that doesn't scale. When the rows would be taller than the box, every card shrinks so they
  fit: nothing scrolls, and nothing is drawn outside the box.
* **Gaps are fixed**: `gap` between columns and between rows. (Only when the gaps between rows
  alone are taller than the box are the rows packed with none.)
* **Reading order**: card `i` is in row `i / columns`, column `i % columns`, so the cards keep
  their order on every resize; only where the rows break changes.
* The used width is centred in the box; rows start at its top.

`Grid.node` builds the view: a column of rows of fixed-size cells, each clipping its card, laid
out by the ordinary layout pass. The geometry's theorems are at the end of this file: the
column count is the largest that fits and at least one, the cells never overlap and stay inside
the box, in reading order. They live here, not with the layout proofs, so an app's claims can
cite them. `Cairn.Layout.Grid` proves the cells land exactly on `Grid.rects` and that hit
testing a point in a cell answers from that cell alone. -/

@[expose] public section

namespace Cairn

-- region: grid-grid
/-- A grid of equal cards whose column count follows the width of its box. -/
structure Grid where
  /-- The narrowest a card is laid out when there's room for it: there are as many columns as
  cards of this width fit (at least one; taken as 1 when 0). -/
  minWidth : Nat
  /-- The cards' aspect ratio, width to height (each taken as 1 when 0). -/
  ratioW : Nat := 1
  ratioH : Nat := 1
  /-- Points between columns and between rows. -/
  gap : Nat := 0
  /-- A fixed height under the scaled part of each card (a caption), not scaled with it. -/
  caption : Nat := 0
deriving Repr, DecidableEq, Inhabited
-- endregion: grid-grid

namespace Grid

def minW (g : Grid) : Nat := max 1 g.minWidth
def rw (g : Grid) : Nat := max 1 g.ratioW
def rh (g : Grid) : Nat := max 1 g.ratioH

-- region: grid-columns
/-- `k` cards of the minimum width, with the gaps between them, fit in `W`. -/
def Fits (g : Grid) (W k : Nat) : Prop := k * g.minW + (k - 1) * g.gap ≤ W

/-- **Columns**: the most cards of the minimum width that fit in `W` with their gaps, and at
least one (`columns_fits`, `le_columns`). -/
def columns (g : Grid) (W : Nat) : Nat := max 1 ((W + g.gap) / (g.minW + g.gap))
-- endregion: grid-columns

instance (g : Grid) (W k : Nat) : Decidable (g.Fits W k) := by unfold Fits; infer_instance

/-- Rows for `n` cards. -/
def rows (g : Grid) (W n : Nat) : Nat := (n + g.columns W - 1) / g.columns W

/-- The gap between rows: `gap`, unless the gaps alone are taller than the box. -/
def vgap (g : Grid) (W H n : Nat) : Nat := if g.gap * (g.rows W n - 1) ≤ H then g.gap else 0

/-- The width each column gets when the cards share the box's width. -/
def widthShare (g : Grid) (W : Nat) : Nat := (W - g.gap * (g.columns W - 1)) / g.columns W

/-- The height each row gets when the rows share the box's height. -/
def heightShare (g : Grid) (W H n : Nat) : Nat :=
  (H - g.vgap W H n * (g.rows W n - 1)) / max 1 (g.rows W n)

/-- A card's width: its share of the width, or less if the rows would be too tall. -/
def cardW (g : Grid) (W H n : Nat) : Nat :=
  min (g.widthShare W) ((g.heightShare W H n - g.caption) * g.rw / g.rh)

/-- A card's height: its width at the aspect ratio, plus the caption (`cardH_aspect`). -/
def cardH (g : Grid) (W H n : Nat) : Nat :=
  min (g.cardW W H n * g.rh / g.rw + g.caption) (g.heightShare W H n)

/-- The width the columns take, gaps included. -/
def usedW (g : Grid) (W H n : Nat) : Nat := (g.columns W - 1) * (g.cardW W H n + g.gap) + g.cardW W H n

/-- Where the first column starts, centring the used width. -/
def offset (g : Grid) (W H n : Nat) : Nat := (W - g.usedW W H n) / 2

-- region: grid-cell
/-- **Card `i`'s rect**, of `n` in the `W × H` box at `(x, y)`: row `i / columns`, column
`i % columns`. -/
def cell (g : Grid) (x y : Int) (W H n i : Nat) : Rect :=
  let c := g.columns W
  ⟨x + ((g.offset W H n + i % c * (g.cardW W H n + g.gap) : Nat) : Int),
   y + ((i / c * (g.cardH W H n + g.vgap W H n) : Nat) : Int),
   g.cardW W H n, g.cardH W H n⟩

/-- Every card's rect, in order. -/
def rects (g : Grid) (x y : Int) (W H n : Nat) : List Rect := (List.range n).map (g.cell x y W H n)
-- endregion: grid-cell

/-! ## The smallest box

`minBox n cols` is the smallest box with `cols` columns (at least one) in which every one of `n`
cards is at least `minWidth` wide: `cols` cards of the minimum width and their gaps across, and
as many rows of the least card height (`minCardH`) and their gaps down. An app hands it, plus
whatever it lays out around the grid, to the host as the window's minimum size
(`App.minSize`), so the cards never shrink below `minWidth`. Its theorems are at the end of the
file. -/

-- region: grid-min-box
/-- The least height of a card `minWidth` wide: its scaled part rounded up, plus the caption. -/
def minCardH (g : Grid) : Nat := (g.minW * g.rh + g.rw - 1) / g.rw + g.caption

/-- **The smallest box with `cols` columns in which every one of `n` cards is at least
`minWidth` wide**, as width and height (`minW_le_cardW`). -/
def minBox (g : Grid) (n cols : Nat) : Nat × Nat :=
  let c := max 1 cols
  let r := (n + c - 1) / c
  (c * g.minW + (c - 1) * g.gap, r * g.minCardH + (r - 1) * g.gap)
-- endregion: grid-min-box

/-! ## The view -/

/-- `xs` in runs of `c` (the last may be shorter). `fuel` bounds the recursion; `chunks` gives
enough. -/
def chunksAux {α : Type} (c : Nat) : Nat → List α → List (List α)
  | 0, _ => []
  | _, [] => []
  | f + 1, xs => xs.take c :: chunksAux c f (xs.drop c)

def chunks {α : Type} (c : Nat) (xs : List α) : List (List α) := chunksAux c xs.length xs

/-- A cell: exactly the card's rect, clipping the card to it, so nothing in one cell paints or
takes a click in another. -/
def cellNode (w h : Nat) (card : Node) : Node :=
  .box { axis := .stack, width := .fixed w, height := .fixed h, clip := true } none [card]

/-- A row's box: the used width, a card high, cells `gap` apart. -/
def rowStyle (g : Grid) (W H n : Nat) : Style :=
  { axis := .row, width := .fixed (g.usedW W H n), height := .fixed (g.cardH W H n), gap := g.gap }

/-- A row of cells. -/
def rowNode (g : Grid) (W H n : Nat) (cells : List Node) : Node := .box (g.rowStyle W H n) none cells

/-- The grid's box: `W × H`, rows `vgap` apart, the used width centred. -/
def style (g : Grid) (W H n : Nat) : Style :=
  { axis := .column, width := .fixed W, height := .fixed H, gap := g.vgap W H n,
    padding := { left := g.offset W H n } }

-- region: grid-node
/-- **The grid as a view**: `W × H` points (a `fixed` box), card `i` drawn by `card w h xs[i]`
at `w × h` points in its cell. The cards keep the order of `xs`. -/
def node {α : Type} (g : Grid) (W H : Nat) (card : Nat → Nat → α → Node) (xs : List α) : Node :=
  let n := xs.length
  let w := g.cardW W H n
  let h := g.cardH W H n
  .box (g.style W H n) none
    ((chunks (g.columns W) (xs.map fun x => cellNode w h (card w h x))).map (g.rowNode W H n))
-- endregion: grid-node

/-! ## The geometry's theorems

That the layout pass puts the cells on these rects, and hit testing, are in
`Cairn.Layout.Grid`. -/

variable (g : Grid)

theorem minW_pos : 1 ≤ g.minW := by simp only [minW]; omega
theorem rw_pos : 1 ≤ g.rw := by simp only [rw]; omega
theorem rh_pos : 1 ≤ g.rh := by simp only [rh]; omega

/-! ## Columns -/

theorem columns_pos (W : Nat) : 1 ≤ g.columns W := by simp only [columns]; omega

/-- `k` columns fit exactly when `k` cards and their gaps fit in the width plus one gap. -/
theorem fits_iff (W k : Nat) (hk : 1 ≤ k) : g.Fits W k ↔ k * (g.minW + g.gap) ≤ W + g.gap := by
  obtain ⟨k, rfl⟩ : ∃ k', k = k' + 1 := ⟨k - 1, by omega⟩
  simp only [Fits, Nat.add_sub_cancel, Nat.mul_add, Nat.add_mul, Nat.one_mul]
  omega

/-- **The column count fits**: one column, or that many cards of the minimum width fit. -/
theorem columns_fits (W : Nat) : g.columns W = 1 ∨ g.Fits W (g.columns W) := by
  by_cases hq : (W + g.gap) / (g.minW + g.gap) ≤ 1
  · left; simp only [columns]; omega
  · right
    have hc : g.columns W = (W + g.gap) / (g.minW + g.gap) := by simp only [columns]; omega
    rw [fits_iff g W _ (by omega), hc]
    exact Nat.div_mul_le_self _ _

/-- **No column count that fits is larger.** -/
theorem le_columns (W k : Nat) (h : g.Fits W k) : k ≤ g.columns W := by
  rcases Nat.eq_zero_or_pos k with rfl | hk
  · exact Nat.zero_le _
  have := (fits_iff g W k hk).1 h
  have hpos : 0 < g.minW + g.gap := by have := minW_pos g; omega
  have : k ≤ (W + g.gap) / (g.minW + g.gap) := (Nat.le_div_iff_mul_le hpos).2 this
  simp only [columns]; omega

/-- **One more column would not fit.** -/
theorem not_fits_succ (W : Nat) : ¬ g.Fits W (g.columns W + 1) := fun h =>
  absurd (le_columns g W _ h) (by omega)

/-- With room for one card of the minimum width, each column's share is at least that wide. -/
theorem minW_le_widthShare (W : Nat) (h : g.Fits W 1) : g.minW ≤ g.widthShare W := by
  have hc := columns_pos g W
  have hf : g.Fits W (g.columns W) := by
    rcases columns_fits g W with h1 | h1
    · rw [h1]; exact h
    · exact h1
  simp only [Fits] at hf
  simp only [widthShare]
  refine (Nat.le_div_iff_mul_le (by omega)).2 ?_
  rw [Nat.mul_comm g.gap, Nat.mul_comm g.minW]
  omega

/-! ## Sizes -/

theorem gaps_le_W (W : Nat) : g.gap * (g.columns W - 1) ≤ W := by
  rcases columns_fits g W with h | h
  · rw [h]; simp only [Nat.sub_self, Nat.mul_zero, Nat.zero_le]
  · simp only [Fits] at h; rw [Nat.mul_comm]; omega

/-- The columns and their gaps fit the width. -/
theorem usedW_le (W H n : Nat) : g.usedW W H n ≤ W := by
  have hc := columns_pos g W
  have hg := gaps_le_W g W
  have hw : g.cardW W H n ≤ g.widthShare W := Nat.min_le_left _ _
  have hs : g.widthShare W * g.columns W ≤ W - g.gap * (g.columns W - 1) :=
    Nat.div_mul_le_self _ _
  have : g.cardW W H n * g.columns W ≤ g.widthShare W * g.columns W := Nat.mul_le_mul_right _ hw
  obtain ⟨c, hc'⟩ : ∃ c, g.columns W = c + 1 := ⟨g.columns W - 1, by omega⟩
  simp only [usedW, hc', Nat.add_sub_cancel, Nat.mul_add, Nat.mul_one] at this hs hg ⊢
  rw [Nat.mul_comm c (g.cardW W H n), Nat.mul_comm c g.gap]
  omega

theorem offset_usedW_le (W H n : Nat) : g.offset W H n + g.usedW W H n ≤ W := by
  have := usedW_le g W H n
  simp only [offset]; omega

theorem vgaps_le (W H n : Nat) : g.vgap W H n * (g.rows W n - 1) ≤ H := by
  simp only [vgap]; split <;> omega

/-- The rows and their gaps fit the height. -/
theorem rows_le (W H n : Nat) (hn : 0 < g.rows W n) :
    (g.rows W n - 1) * (g.cardH W H n + g.vgap W H n) + g.cardH W H n ≤ H := by
  have hv := vgaps_le g W H n
  have hh : g.cardH W H n ≤ g.heightShare W H n := Nat.min_le_right _ _
  have hs : g.heightShare W H n * max 1 (g.rows W n) ≤ H - g.vgap W H n * (g.rows W n - 1) :=
    Nat.div_mul_le_self _ _
  have hm : max 1 (g.rows W n) = g.rows W n := by omega
  rw [hm] at hs
  have : g.cardH W H n * g.rows W n ≤ g.heightShare W H n * g.rows W n := Nat.mul_le_mul_right _ hh
  obtain ⟨r, hr⟩ : ∃ r, g.rows W n = r + 1 := ⟨g.rows W n - 1, by omega⟩
  simp only [hr, Nat.add_sub_cancel, Nat.mul_add, Nat.mul_one] at this hs hv ⊢
  rw [Nat.mul_comm r (g.cardH W H n), Nat.mul_comm r (g.vgap W H n)]
  omega

/-- **Aspect kept**: when the box is tall enough for the captions, a card is as tall as its
width at the aspect ratio, plus the caption. -/
theorem cardH_aspect (W H n : Nat) (h : g.caption ≤ g.heightShare W H n) :
    g.cardH W H n = g.cardW W H n * g.rh / g.rw + g.caption := by
  have hw : g.cardW W H n ≤ (g.heightShare W H n - g.caption) * g.rw / g.rh := Nat.min_le_right _ _
  have h1 : g.cardW W H n * g.rh ≤ (g.heightShare W H n - g.caption) * g.rw :=
    (Nat.le_div_iff_mul_le (rh_pos g)).1 hw
  have h2 : g.cardW W H n * g.rh / g.rw ≤ g.heightShare W H n - g.caption :=
    (Nat.div_le_iff_le_mul_add_pred (rw_pos g)).2 (by
      rw [Nat.mul_comm] at h1 ⊢
      have := Nat.mul_comm g.rw (g.heightShare W H n - g.caption); omega)
  simp only [cardH]; omega

/-- **Gaps fixed**: whenever the gaps between rows fit the height, rows are `gap` apart. -/
theorem vgap_eq (W H n : Nat) (h : g.gap * (g.rows W n - 1) ≤ H) : g.vgap W H n = g.gap := by
  simp only [vgap, h, ↓reduceIte]

/-! ## Cells -/

theorem row_lt_rows (W n i : Nat) (hi : i < n) : i / g.columns W < g.rows W n := by
  have hc := columns_pos g W
  have hd := Nat.div_mul_le_self i (g.columns W)
  simp only [rows]
  refine (Nat.le_div_iff_mul_le (by omega)).2 ?_
  rw [Nat.succ_mul]; omega

theorem mul_le_of_le {a b s : Nat} (h : a ≤ b) : a * s ≤ b * s := Nat.mul_le_mul_right _ h

/-- `a < b` rows (or columns) of pitch `s ≥ w` apart: the earlier ends before the later starts. -/
theorem pitch_lt {a b s w : Nat} (h : a < b) (hw : w ≤ s) : a * s + w ≤ b * s := by
  have : (a + 1) * s ≤ b * s := Nat.mul_le_mul_right _ h
  rw [Nat.add_mul, Nat.one_mul] at this; omega

/-- **Inside**: every card's rect is inside the grid's box. -/
theorem cell_inside (x y : Int) (W H n i : Nat) (hi : i < n) :
    (g.cell x y W H n i).inside ⟨x, y, W, H⟩ := by
  have hc := columns_pos g W
  have hcol : i % g.columns W ≤ g.columns W - 1 := by
    have := Nat.mod_lt i (show 0 < g.columns W by omega); omega
  have hrow : i / g.columns W ≤ g.rows W n - 1 := by
    have := row_lt_rows g W n i hi; generalize i / g.columns W = q at this ⊢; omega
  have hx := mul_le_of_le (s := g.cardW W H n + g.gap) hcol
  have hy := mul_le_of_le (s := g.cardH W H n + g.vgap W H n) hrow
  have hu := offset_usedW_le g W H n
  have hv := rows_le g W H n (Nat.lt_of_le_of_lt (Nat.zero_le _) (row_lt_rows g W n i hi))
  simp only [usedW] at hu
  have hX : g.offset W H n + i % g.columns W * (g.cardW W H n + g.gap) + g.cardW W H n ≤ W := by
    omega
  have hY : i / g.columns W * (g.cardH W H n + g.vgap W H n) + g.cardH W H n ≤ H := by omega
  generalize g.offset W H n + i % g.columns W * (g.cardW W H n + g.gap) = X at hX
  generalize i / g.columns W * (g.cardH W H n + g.vgap W H n) = Y at hY
  simp only [cell, Rect.inside]
  omega

/-- **Reading order**: a later card is in a lower row (it starts below the earlier one's
bottom), or in the same row and to the right. -/
theorem cell_before (x y : Int) (W H n i j : Nat) (hij : i < j) :
    let a := g.cell x y W H n i
    let b := g.cell x y W H n j
    a.y + a.h ≤ b.y ∨ (a.y = b.y ∧ a.x + a.w ≤ b.x) := by
  have hc := columns_pos g W
  have hi := Nat.div_add_mod i (g.columns W)
  have hj := Nat.div_add_mod j (g.columns W)
  simp only [cell]
  by_cases hr : i / g.columns W < j / g.columns W
  · left
    have := pitch_lt (s := g.cardH W H n + g.vgap W H n) (w := g.cardH W H n) hr (by omega)
    omega
  · right
    have hr' : i / g.columns W = j / g.columns W := by
      have := Nat.div_le_div_right (c := g.columns W) (Nat.le_of_lt hij); omega
    have hm : i % g.columns W < j % g.columns W := by
      rw [hr'] at hi; omega
    have := pitch_lt (s := g.cardW W H n + g.gap) (w := g.cardW W H n) hm (by omega)
    refine ⟨by rw [hr'], by omega⟩

/-- **No overlap**: two different cards' rects are disjoint. -/
theorem cell_disjoint (x y : Int) (W H n i j : Nat) (hij : i ≠ j) :
    (g.cell x y W H n i).disjoint (g.cell x y W H n j) := by
  rcases Nat.lt_or_gt_of_ne hij with h | h
  · rcases cell_before g x y W H n i j h with h' | ⟨-, h'⟩ <;> unfold Rect.disjoint <;> omega
  · rcases cell_before g x y W H n j i h with h' | ⟨-, h'⟩ <;> unfold Rect.disjoint <;> omega

theorem rects_length (x y : Int) (W H n : Nat) : (g.rects x y W H n).length = n := by
  simp only [rects, List.length_map, List.length_range]

theorem rects_getElem (x y : Int) (W H n i : Nat) (h : i < (g.rects x y W H n).length) :
    (g.rects x y W H n)[i] = g.cell x y W H n i := by
  simp only [rects, List.getElem_map, List.getElem_range]

/-- The rects in order: pairwise disjoint, and each in reading order before the next. -/
theorem rects_pairwise (x y : Int) (W H n : Nat) :
    (g.rects x y W H n).Pairwise fun a b =>
      a.disjoint b ∧ (a.y + a.h ≤ b.y ∨ (a.y = b.y ∧ a.x + a.w ≤ b.x)) := by
  simp only [rects]
  refine List.pairwise_map.2 ?_
  refine List.Pairwise.imp_of_mem ?_ (List.pairwise_lt_range (n := n))
  intro i j _ _ hij
  exact ⟨cell_disjoint g x y W H n i j (by omega), cell_before g x y W H n i j hij⟩

theorem rects_inside (x y : Int) (W H n : Nat) : ∀ r ∈ g.rects x y W H n, r.inside ⟨x, y, W, H⟩ := by
  simp only [rects, List.mem_map, List.mem_range]
  rintro r ⟨i, hi, rfl⟩
  exact cell_inside g x y W H n i hi

/-! ## The smallest box

* **At or above it, every card is at least `minWidth` wide** (`minW_le_cardW`, `minBox_cells`):
  a wider box has as many columns or more, so no more rows, and a taller one only more room.
* **It is the smallest**: it has exactly `cols` columns (`columns_minBox`); a narrower box has
  fewer columns, or with one column cards narrower than `minWidth` (`minBox_narrower`); a shorter
  box with `cols` columns has cards narrower than `minWidth` (`minBox_shorter`, when the gap is
  no taller than a card). -/


/-- Rounding up: `q = ⌈a / b⌉` covers `a` (`a ≤ q * b`) and one less doesn't (`(q - 1) * b < a`
when `a > 0`). -/
theorem ceil_spec (a b : Nat) (hb : 1 ≤ b) :
    a ≤ (a + b - 1) / b * b ∧ (0 < a → ((a + b - 1) / b - 1) * b < a) := by
  have h1 := Nat.div_add_mod (a + b - 1) b
  have h2 := Nat.mod_lt (a + b - 1) (show 0 < b by omega)
  generalize (a + b - 1) / b = q at h1 ⊢
  generalize (a + b - 1) % b = m at h1 h2
  rw [Nat.mul_comm] at h1
  refine ⟨by omega, fun ha => ?_⟩
  rw [Nat.sub_mul, Nat.one_mul]
  omega

/-- Rows only get fewer with more columns: `⌈n / C⌉ ≤ ⌈n / c⌉` when `1 ≤ c ≤ C`. -/
theorem ceil_div_anti (n c C : Nat) (hc : 1 ≤ c) (hC : c ≤ C) :
    (n + C - 1) / C ≤ (n + c - 1) / c := by
  have ⟨h1, _⟩ := ceil_spec n c hc
  generalize (n + c - 1) / c = r at h1 ⊢
  have : r * c ≤ r * C := Nat.mul_le_mul_left _ hC
  refine (Nat.div_le_iff_le_mul_add_pred (by omega)).2 ?_
  rw [Nat.mul_comm C r]
  omega

/-- The columns of a box at least `minBox`'s width: at least `cols`. -/
theorem le_columns_minBox (n cols W : Nat) (hW : (g.minBox n cols).1 ≤ W) :
    max 1 cols ≤ g.columns W :=
  le_columns g W _ (by simp only [Fits, minBox] at hW ⊢; exact hW)

/-- **At or above `minBox`, every card is at least `minWidth` wide.** -/
theorem minW_le_cardW (n cols W H : Nat) (hn : 0 < n) (hW : (g.minBox n cols).1 ≤ W)
    (hH : (g.minBox n cols).2 ≤ H) : g.minW ≤ g.cardW W H n := by
  have hc1 : 1 ≤ max 1 cols := Nat.le_max_left _ _
  have hcols := le_columns_minBox g n cols W hW
  -- Wide enough: one card of the minimum width fits, so each column's share is that wide.
  have hws : g.minW ≤ g.widthShare W := minW_le_widthShare g W (by
    simp only [Fits, minBox] at hW ⊢
    have : g.minW ≤ max 1 cols * g.minW := Nat.le_mul_of_pos_left _ hc1
    omega)
  -- Tall enough: no more rows than `minBox` counted, each with room for `minCardH`.
  have hrows : g.rows W n ≤ (n + max 1 cols - 1) / max 1 cols :=
    ceil_div_anti n _ _ hc1 hcols
  have hR : 1 ≤ g.rows W n := by
    have := columns_pos g W
    simp only [rows]
    exact (Nat.le_div_iff_mul_le (by omega)).2 (by omega)
  simp only [minBox] at hH
  generalize (n + max 1 cols - 1) / max 1 cols = r at hrows hH
  generalize hRdef : g.rows W n = R at hrows hR
  have hRm : R * g.minCardH ≤ r * g.minCardH := Nat.mul_le_mul_right _ hrows
  have hroom : R * g.minCardH + (R - 1) * g.gap ≤ H := by
    have : (R - 1) * g.gap ≤ (r - 1) * g.gap := Nat.mul_le_mul_right _ (by omega)
    omega
  have hv : g.vgap W H n = g.gap := by
    apply vgap_eq; rw [hRdef, Nat.mul_comm]; omega
  have hhs : g.minCardH ≤ g.heightShare W H n := by
    simp only [heightShare, hv, hRdef, show max 1 R = R by omega]
    refine (Nat.le_div_iff_mul_le (by omega)).2 ?_
    rw [Nat.mul_comm g.gap, Nat.mul_comm g.minCardH]
    omega
  -- So the height allows a card `minWidth` wide.
  have ⟨hq, _⟩ := ceil_spec (g.minW * g.rh) g.rw (rw_pos g)
  have hq' : (g.minW * g.rh + g.rw - 1) / g.rw ≤ g.heightShare W H n - g.caption := by
    simp only [minCardH] at hhs; omega
  have hmul : g.minW * g.rh ≤ (g.heightShare W H n - g.caption) * g.rw :=
    Nat.le_trans hq (Nat.mul_le_mul_right _ hq')
  have hhw : g.minW ≤ (g.heightShare W H n - g.caption) * g.rw / g.rh :=
    (Nat.le_div_iff_mul_le (rh_pos g)).2 hmul
  simp only [cardW]
  omega

/-- **Every card's rect is at least `minWidth` wide** in a box at least `minBox`. -/
theorem minBox_cells (x y : Int) (n cols W H : Nat) (hW : (g.minBox n cols).1 ≤ W)
    (hH : (g.minBox n cols).2 ≤ H) : ∀ r ∈ g.rects x y W H n, (g.minW : Int) ≤ r.w := by
  simp only [rects, List.mem_map, List.mem_range]
  rintro r ⟨i, hi, rfl⟩
  have := minW_le_cardW g n cols W H (by omega) hW hH
  simp only [cell]
  omega

/-- **`minBox` has exactly `cols` columns** (at least one). -/
theorem columns_minBox (n cols : Nat) : g.columns (g.minBox n cols).1 = max 1 cols := by
  have hc1 : 1 ≤ max 1 cols := Nat.le_max_left _ _
  have hpos : 0 < g.minW + g.gap := by have := minW_pos g; omega
  have : max 1 cols * g.minW + (max 1 cols - 1) * g.gap + g.gap = max 1 cols * (g.minW + g.gap) := by
    obtain ⟨c, hc⟩ : ∃ c, max 1 cols = c + 1 := ⟨max 1 cols - 1, by omega⟩
    rw [hc, Nat.add_sub_cancel, Nat.mul_add, Nat.add_mul, Nat.add_mul]
    omega
  simp only [columns, minBox, this, Nat.mul_div_cancel _ hpos]
  omega

/-- **No narrower box will do**: narrower than `minBox`, a box has fewer than `cols` columns, or
(at one column) cards narrower than `minWidth`. -/
theorem minBox_narrower (n cols W H : Nat) (hW : W < (g.minBox n cols).1) :
    g.columns W < max 1 cols ∨ g.cardW W H n < g.minW := by
  by_cases h1 : g.columns W = 1
  · by_cases hc : max 1 cols = 1
    · right
      have hws : g.widthShare W = W := by simp only [widthShare, h1, Nat.sub_self, Nat.mul_zero,
        Nat.sub_zero, Nat.div_one]
      simp only [minBox, hc, Nat.one_mul, Nat.sub_self, Nat.zero_mul, Nat.add_zero] at hW
      simp only [cardW, hws]
      omega
    · left; have := Nat.le_max_left 1 cols; omega
  · left
    have hf : g.Fits W (g.columns W) := (columns_fits g W).resolve_left h1
    by_cases hlt : g.columns W < max 1 cols
    · exact hlt
    · exfalso
      -- `columns W ≥ cols` cards of the minimum width fit, so `cols` of them do.
      have hge : max 1 cols ≤ g.columns W := by omega
      simp only [Fits] at hf
      simp only [minBox] at hW
      have : max 1 cols * g.minW ≤ g.columns W * g.minW := Nat.mul_le_mul_right _ hge
      have : (max 1 cols - 1) * g.gap ≤ (g.columns W - 1) * g.gap :=
        Nat.mul_le_mul_right _ (by omega)
      omega

/-- **No shorter box will do**: with `cols` columns and a gap no taller than a card, a box
shorter than `minBox` has cards narrower than `minWidth`. -/
theorem minBox_shorter (n cols W H : Nat) (hn : 0 < n) (hcols : g.columns W = max 1 cols)
    (hgap : g.gap ≤ g.minCardH) (hH : H < (g.minBox n cols).2) : g.cardW W H n < g.minW := by
  have hc1 : 1 ≤ max 1 cols := Nat.le_max_left _ _
  have hrows : g.rows W n = (n + max 1 cols - 1) / max 1 cols := by simp only [rows, hcols]
  simp only [minBox] at hH
  rw [← hrows] at hH
  have hR : 1 ≤ g.rows W n := by
    rw [hrows]; exact (Nat.le_div_iff_mul_le (by omega)).2 (by omega)
  generalize hRdef : g.rows W n = R at hH hR
  -- Each row gets less than `minCardH`, with the gaps or without them.
  have hhs : g.heightShare W H n < g.minCardH := by
    simp only [heightShare, hRdef, show max 1 R = R by omega]
    refine (Nat.div_lt_iff_lt_mul (by omega)).2 ?_
    have h1 : g.gap * (R - 1) ≤ g.minCardH * (R - 1) := Nat.mul_le_mul_right _ hgap
    have h2 : g.minCardH * R = g.minCardH * (R - 1) + g.minCardH := by
      obtain ⟨k, rfl⟩ : ∃ k, R = k + 1 := ⟨R - 1, by omega⟩
      rw [Nat.add_sub_cancel, Nat.mul_add, Nat.mul_one]
    rw [Nat.mul_comm (R - 1) g.gap, Nat.mul_comm R g.minCardH] at hH
    simp only [vgap, hRdef]
    split <;> omega
  -- So the height allows no card `minWidth` wide.
  have ⟨_, hq⟩ := ceil_spec (g.minW * g.rh) g.rw (rw_pos g)
  have hpos : 0 < g.minW * g.rh := Nat.mul_pos (minW_pos g) (rh_pos g)
  have hq := hq hpos
  have hle : g.heightShare W H n - g.caption ≤ (g.minW * g.rh + g.rw - 1) / g.rw - 1 := by
    simp only [minCardH] at hhs; omega
  have hlt : (g.heightShare W H n - g.caption) * g.rw < g.minW * g.rh :=
    Nat.lt_of_le_of_lt (Nat.mul_le_mul_right _ hle) hq
  have : (g.heightShare W H n - g.caption) * g.rw / g.rh < g.minW :=
    (Nat.div_lt_iff_lt_mul (rh_pos g)).2 hlt
  simp only [cardW]
  omega

end Grid

end Cairn
