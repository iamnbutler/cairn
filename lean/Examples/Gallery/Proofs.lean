import Examples.Gallery
import Cairn.Layout
import Cairn.Frame.Layout
import Cairn.Runtime
import Cairn.Claims.Deliver

/-! # Gallery: theorems about the view, layout and the runtime

The moves' evidence, the invariant ^504 and the flow ^505 are checked where they are declared,
in `Examples.Gallery`. Here:

* **Sizes.** Every tile's image measures 200 × 150 whatever is known of it, so loading, a late
  reply or a failure never moves anything (`tileImage_size`).
* **Presence.** Fit and Reload are on screen in every state, and nothing else is a control: the
  tiles aren't (`view_refs`, `reload_in_frame`).
* ^504 holds in every state the running app reaches (`freshLoads_on_screen`). -/

namespace Examples.Gallery
open Cairn Cairn.Claims Cairn.Layout Cairn.Runtime

/-! ## Sizes -/

-- region: gallery-size
/-- **A tile's image has its size before its pixels**: 200 × 150 while loading, once loaded
at any pixel size, and when the load failed. -/
theorem tileImage_size (m : TextMetrics) (aw : Int) (s : State) (src : String) :
    (measure m aw (tileImage s src)).size = ⟨tileW, tileH⟩ :=
  measure_image m aw _

/-- …so two states that differ only in what is known of the images give tiles the same size. -/
theorem tileImage_size_any (m : TextMetrics) (aw : Int) (s s' : State) (src : String) :
    (measure m aw (tileImage s src)).size = (measure m aw (tileImage s' src)).size := by
  rw [tileImage_size, tileImage_size]
-- endregion: gallery-size

/-! ## Presence -/

theorem controlsList_map (f : Tile → Node) : ∀ xs : List Tile,
    Node.controlsList (xs.map f) = xs.flatMap fun x => (f x).controls
  | [] => rfl
  | x :: xs => by simp only [List.map_cons, Node.controlsList, List.flatMap_cons, controlsList_map f xs]

theorem tile_controls (s : State) (t : Tile) : (tile s t).controls = [] := by
  simp only [tile, tileImage, line, Node.controls, Node.controlsList, controls_image, Option.toList,
    List.append_nil]

theorem tiles_controls (s : State) : ∀ ts : List Tile, (ts.flatMap fun t => (tile s t).controls) = []
  | [] => rfl
  | t :: ts => by rw [List.flatMap_cons, tile_controls, tiles_controls s ts]; rfl

-- region: gallery-presence
/-- The view's controls, in every state: Fit, then Reload. The tiles are no controls. -/
theorem view_refs (s : State) (ui : UI) :
    (view s ui).controls.map (·.ref) = [fitRef, reloadRef] := by
  simp only [view, header, tileRow, button, line, Node.controls, Node.controlsList, controlsList_map,
    tiles_controls, Option.toList, List.append_nil, List.nil_append,
    List.cons_append, List.map_cons]
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
