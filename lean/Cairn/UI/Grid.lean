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
out by the ordinary layout pass. `Cairn.Layout.Grid` proves the cells land exactly on
`Grid.rects`, that they never overlap and stay inside the box, that the column count is the
largest that fits, and that hit testing a point in a cell answers from that cell alone. -/

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

end Grid

end Cairn
