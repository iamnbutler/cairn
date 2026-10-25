import Examples.Gallery
import Cairn.Layout
import Cairn.Layout.Grid
import Cairn.Frame.Layout
import Cairn.Runtime
import Cairn.Claims.Deliver

/-! # Gallery: theorems about the view, layout and the runtime

The moves' evidence, the invariant ^504 and the flow ^505 are checked where they are declared,
in `Examples.Gallery`. Here:

* **Sizes.** A tile's image measures the size its cell gives it whatever is known of it, so
  loading, a late reply or a failure never moves anything (`tileImage_size`).
* **The grid** (^510). Laid out at any window size, the tiles land exactly on `tileRects`
  (`tiles_laid`), which never overlap, read in order and stay in the window (`tilesFit`, in
  `Examples.Gallery`); a point in a tile's rect hits only that tile (`tiles_hit`).
* **Presence.** Fit, Reload, the six tiles in order, Load 24 and Cancel are on screen in every
  state and at every size, and nothing else is a control: the thumbnails aren't (`view_refs`,
  `reload_in_frame`).
* ^504 holds in every state the running app reaches (`freshLoads_on_screen`). -/

namespace Examples.Gallery
open Cairn Cairn.Claims Cairn.Layout Cairn.Runtime

/-! ## Sizes -/

-- region: gallery-size
/-- **A tile's image has its size before its pixels**: `w × h` while loading, once loaded
at any pixel size, and when the load failed. -/
theorem tileImage_size (m : TextMetrics) (aw : Int) (s : State) (w h : Nat) (src : String) :
    (measure m aw (tileImage s w h src)).size = ⟨w, h⟩ :=
  measure_image m aw _

/-- …so two states that differ only in what is known of the images give tiles the same size. -/
theorem tileImage_size_any (m : TextMetrics) (aw : Int) (s s' : State) (w h : Nat) (src : String) :
    (measure m aw (tileImage s w h src)).size = (measure m aw (tileImage s' w h src)).size := by
  rw [tileImage_size, tileImage_size]

/-! ## The grid -/

/-- The tiles' grid in a laid-out view: the gallery column's second child. -/
def tilesOf (l : Laid) : Laid := (l.children.headD default).children.getD 1 default

-- region: gallery-laid
/-- The layout pass puts the tiles' grid at `(gridX, gridY)`, `gridW × gridH`: the room the
window leaves under the header, beside the thumbnails. -/
theorem tilesOf_layout (m : TextMetrics) (s : State) (ui : UI) :
    ∃ c aw, tilesOf (layout m ui.size (view s ui)) =
      arrange m c ⟨gridX, gridY, gridW ui.size, gridH ui.size⟩ (measure m aw (tilesNode s ui)) := by
  simp only [tilesOf, layout, view, galleryColumn, Layout.measure, measureList, rootRect, arrange,
    arrangeList, childRects, lineRects, lineOf, Line.go, Laid.children, List.map_cons, List.map_nil,
    Sized.item, Sized.sizings, List.headD_cons, List.getD_cons_succ, List.getD_cons_zero, mainSize,
    header, Item.mainSizing, Item.crossSizing, Bool.false_eq_true, ↓reduceIte, mainBase,
    crossPlace, startOffset, spacing, mkRect, Rect.inset]
  apply Exists.intro; apply Exists.intro
  congr 1

/-- **The tiles land on `tileRects`**, for every window size, state and metrics. With
`tilesFit`, this is ^510's evidence about the screen. -/
theorem tiles_laid (m : TextMetrics) (s : State) (ui : UI) :
    (Grid.cells (tilesOf (layout m ui.size (view s ui)))).map Laid.rect = tileRects ui.size := by
  obtain ⟨c, aw, h⟩ := tilesOf_layout m s ui
  rw [h, tilesNode, Grid.cells_rects]
  rfl

/-- **A point in a tile hits that tile.** In the laid-out tiles, a point inside tile `i`'s rect
hits exactly what tile `i`'s cell alone would: no other tile can take the click. -/
theorem tiles_hit (m : TextMetrics) (s : State) (ui : UI) (i : Nat) (hi : i < tiles.length)
    (p : Point)
    (hp : (tileGrid.cell gridX gridY (gridW ui.size) (gridH ui.size) tiles.length i).contains p) :
    ∃ k, (Grid.cells (tilesOf (layout m ui.size (view s ui))))[i]? = some k ∧
      hitTarget (tilesOf (layout m ui.size (view s ui))) p = hitTarget k p := by
  obtain ⟨c, aw, h⟩ := tilesOf_layout m s ui
  rw [h, tilesNode]
  obtain ⟨k, hk, -, hh⟩ := Grid.hitTarget_cell tileGrid m aw c
    ⟨gridX, gridY, gridW ui.size, gridH ui.size⟩ (gridW ui.size) (gridH ui.size) (tile s ui)
    tiles.zipIdx i (by rw [List.length_zipIdx]; exact hi) p
    (by rw [List.length_zipIdx]; exact hp)
  exact ⟨k, hk, hh⟩
-- endregion: gallery-laid
-- endregion: gallery-size

/-! ## Presence -/

theorem tile_refs (s : State) (ui : UI) (w h : Nat) (t : Tile × Nat) :
    (tile s ui w h t).controls.map (·.ref) = [tileRef t.2] := by
  simp only [tile, tileImage, line, Node.controls, Node.controlsList, controls_image, Option.toList,
    List.append_nil, List.map_cons, List.map_nil]

theorem tiles_refs (s : State) (ui : UI) (w h : Nat) : ∀ ts : List (Tile × Nat),
    (ts.flatMap fun t => (tile s ui w h t).controls).map (·.ref) = ts.map (tileRef ·.2)
  | [] => rfl
  | t :: ts => by
    rw [List.flatMap_cons, List.map_append, tile_refs, tiles_refs s ui w h ts]; rfl

theorem thumbs_controls (s : State) : ∀ xs : List String, Node.controlsList (xs.map (thumb s)) = []
  | [] => rfl
  | x :: xs => by
    simp only [List.map_cons, Node.controlsList, thumb, controls_image,
      thumbs_controls s xs, List.append_nil]

-- region: gallery-presence
/-- The view's controls, in every state and at every size: Fit, Reload, the six tiles in
order, Load 24, then Cancel. The thumbnails are no controls. -/
theorem view_refs (s : State) (ui : UI) :
    (view s ui).controls.map (·.ref) =
      [fitRef, reloadRef] ++ (List.range 6).map tileRef ++ [manyRef, cancelRef] := by
  simp only [view, galleryColumn, manyColumn, header, tilesNode, thumbRow, thumbs_controls, button,
    line, Node.controls, Node.controlsList, Grid.node_controls, Option.toList, List.append_nil,
    List.nil_append, List.cons_append, List.map_cons, List.map_append, tiles_refs]
  rfl
-- endregion: gallery-presence

/-- **Reload is in every frame's accessibility tree**, for any metrics and window. -/
theorem reload_in_frame (s : State) (ui ui' : UI) (m : TextMetrics) (w : Size) :
    reloadRef ∈ (Frame.ofLaid ui' (layout m w (view s ui))).ax.toList.filterMap AxNode.control := by
  rw [Frame.controls_ofLaid_layout, view_refs]; simp

/-! ## Through the runtime -/

/-- ^504 on screen: after any events, every pending load has an id below the next request's. -/
theorem freshLoads_on_screen (cfg : Config) (size : Size) (scale : Nat) (es : List Event) :
    freshLoads.holds (steps app cfg (start app cfg size scale) es).1.app :=
  freshLoads.reachableAll _ (steps_reachableAll machine app rfl rfl rfl cfg size scale es)

end Examples.Gallery
