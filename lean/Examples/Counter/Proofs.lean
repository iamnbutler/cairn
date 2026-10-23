import Examples.Counter
import Cairn.Layout
import Cairn.Frame.Layout
import Cairn.Runtime

/-! # Counter: theorems about the view, the frame and the runtime

The moves' own evidence (`sound`), the invariant ^6 and the flows ^4 and ^5 are checked where
they are declared, in `Examples.Counter`. This file adds what depends on the view and layout:
**Reset is on screen exactly when the count is above zero**, and every control is pressable. -/

namespace Examples.Counter
open Cairn Cairn.Claims Cairn.Layout Cairn.Runtime

/-! ## Presence of ^2 -/

/-- The view's controls, in paint order: Increment, then Reset when it is enabled. -/
theorem view_refs (s : State) (ui : UI) :
    (view s ui).controls.map (·.ref) =
      incrementRef :: (if resetEnabled s then [resetRef] else []) := by
  unfold view
  cases resetEnabled s <;>
    simp [button, Node.controls, Node.controlsList, Option.toList]

/-- **Presence of ^2** in the view: Reset's control is there exactly when reset is enabled. -/
theorem reset_present_iff (s : State) (ui : UI) :
    resetRef ∈ (view s ui).controls.map (·.ref) ↔ resetEnabled s = true := by
  rw [view_refs]
  cases resetEnabled s <;> simp [incrementRef, resetRef]

/-- Presence, stated against the move: ^2's control is on screen exactly when the move is
enabled. -/
theorem reset_present_iff_enabled (s : State) (ui : UI) :
    resetRef ∈ (view s ui).controls.map (·.ref) ↔ reset.enabled s = true :=
  reset_present_iff s ui

/-- …and in the counter's own terms: Reset is there exactly when the count is above zero. -/
theorem reset_present_iff_count (s : State) (ui : UI) :
    resetRef ∈ (view s ui).controls.map (·.ref) ↔ 0 < s.count := by
  rw [reset_present_iff]; simp [resetEnabled]

/-- Increment is always there. -/
theorem increment_present (s : State) (ui : UI) :
    incrementRef ∈ (view s ui).controls.map (·.ref) := by
  rw [view_refs]; exact List.mem_cons_self ..

/-- **Presence through layout and the frame**: in the accessibility tree of the frame, for any
metrics and window size, ^2 is there exactly when the count is above zero. -/
theorem reset_in_frame_iff (s : State) (ui ui' : UI) (m : TextMetrics) (w : Size) :
    resetRef ∈ (Frame.ofLaid ui' (layout m w (view s ui))).ax.toList.filterMap AxNode.control ↔
      0 < s.count := by
  rw [Frame.controls_ofLaid_layout]; exact reset_present_iff_count s ui

/-- …and in every frame the running app shows (the runtime lays out `view` with the config's
layout, which is `layout` unless a test swaps it). -/
theorem reset_on_screen_iff (cfg : Config) (h : cfg.layout = layout) (st : Runtime.State State)
    (ui : UI) (hl : st.laid = relayout app cfg st.app ui) :
    resetRef ∈ (Frame.ofLaid st.ui st.laid).ax.toList.filterMap AxNode.control ↔
      0 < st.app.count := by
  rw [hl, relayout, h]; exact reset_in_frame_iff st.app ui st.ui cfg.metrics ui.size

/-! ## Pressable, for concrete states -/

/-- The count at three in the default 480×320 window, Reset focused. -/
def threeUI : UI := { size := ⟨480, 320⟩, focus := some resetRef }

/-- **Every control is pressable at its centre** at count 3 (mono metrics): the hit test at the
centre of each control's visible rect returns that control. The kernel evaluates the layout and
`checkPressable`; `hitTest_center_of_check` turns that into the theorem. -/
theorem three_pressable :
    ∀ t ∈ targets (layout TextMetrics.mono threeUI.size (view { count := 3 } threeUI)),
      hitTest (layout TextMetrics.mono threeUI.size (view { count := 3 } threeUI))
        t.visible.center = some t.control :=
  hitTest_center_of_check (by decide +kernel)

/-- …and at count 0, where only Increment is there. -/
theorem zero_pressable :
    ∀ t ∈ targets (layout TextMetrics.mono ⟨480, 320⟩ (view {} {})),
      hitTest (layout TextMetrics.mono ⟨480, 320⟩ (view {} {})) t.visible.center =
        some t.control :=
  hitTest_center_of_check (by decide +kernel)

end Examples.Counter
