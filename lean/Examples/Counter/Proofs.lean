import Examples.Counter
import Cairn.Layout
import Cairn.Frame.Layout
import Cairn.Runtime

/-! # Counter: theorems about the view, the frame and the runtime

The moves' own evidence (`sound`) and the flows ^4 and ^5 are checked where
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
    simp [bar, countRow, button, Node.controls, Node.controlsList, Option.toList]

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

/-! ## Pressable, in every state -/

/-- The view, unfolded: a `fill × fill` column whose children are all `fixed` or `fill` on both
axes, with text only in clipped boxes (`Cairn.Layout.FitsIn`). -/
theorem view_eq (s : State) (ui : UI) : view s ui =
    .box { width := .fill, height := .fill, padding := ⟨40, 40, 40, 40⟩, gap := 16,
           background := some bg, clip := true } none
      ([ bar s.count,
         countRow s.count,
         button ui incrementRef "Increment" green greenDark ] ++
       (if resetEnabled s then [button ui resetRef "Reset" red redDark] else [])) := rfl

theorem barWidth_le (n : Nat) : barWidth n ≤ 400 := by
  unfold barWidth; omega

theorem view_kids {s : State} {ui : UI} {k : Node}
    (hk : k ∈ [bar s.count, countRow s.count, button ui incrementRef "Increment" green greenDark] ++
      (if resetEnabled s = true then [button ui resetRef "Reset" red redDark] else [])) :
    k = bar s.count ∨ k = countRow s.count ∨
      k = button ui incrementRef "Increment" green greenDark ∨
      k = button ui resetRef "Reset" red redDark := by
  rcases List.mem_append.1 hk with hk | hk
  · simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
    rcases hk with h | h | h <;> simp only [h, true_or, or_true]
  · split at hk
    · simp only [List.mem_cons, List.not_mem_nil, or_false] at hk; simp only [hk, or_true]
    · simp at hk

/-- **The view is rigid and fits** any window at least 480 × 256: Counter's minimum. -/
theorem view_fitsIn (s : State) (ui : UI) {w h : Int} (hw : 480 ≤ w) (hh : 256 ≤ h) :
    FitsIn (view s ui) w h := by
  have hb := barWidth_le s.count
  rw [view_eq]
  refine .line (by decide) ⟨by decide, by decide, by decide, by decide⟩ ?_ ?_ (by simp) ?_ ?_ ?_
  · simp only [contentW]; omega
  · simp only [contentH]; omega
  · cases resetEnabled s <;>
      simp only [lineBase, Axis.horiz, mainSz, nodeSizings, bar, button, countRow, fixedOf, gaps,
        mainIn, contentH, List.map, List.sum_cons, List.sum_nil, List.length, List.cons_append,
        List.nil_append, List.append_nil, Bool.false_eq_true, ↓reduceIte] <;> omega
  · intro k hk
    rcases view_kids hk with rfl | rfl | rfl | rfl <;>
      simp only [nodeSizings, bar, button, countRow, Sizing.isHug, Axis.horiz, crossSz, fixedOf,
        crossIn, contentW, Bool.false_eq_true, ↓reduceIte, true_and] <;> omega
  · intro k hk len _ hfix
    rcases view_kids hk with rfl | rfl | rfl | rfl
    · have hl : len = 20 := hfix 20 rfl
      subst hl
      refine .line (by simp) ⟨by simp, by simp, by simp, by simp⟩
        ?_ ?_ (by simp) ?_ (by simp) (by simp)
      all_goals simp only [bar, contentW, contentH, wOf, hOf, lenIn, crossSz, nodeSizings,
        lineBase, mainIn, Axis.horiz, List.map_nil, List.sum_nil, gaps, List.length_nil,
        Bool.false_eq_true, ↓reduceIte]
      all_goals omega
    · exact .clipped rfl (by simp [Node.isText]) (by simp [countRow])
    all_goals
      have hl : len = 44 := hfix 44 rfl
      subst hl
      refine .clipped rfl (by simp [Node.isText]) fun _ => ?_
      simp only [button, wOf, hOf, lenIn, crossSz, nodeSizings, Axis.horiz, Bool.false_eq_true,
        ↓reduceIte]
      omega

/-- **Every control is pressable at its centre, in every state**, with any text metrics and
any window at least 480 × 256 (the default is 480 × 320): the hit test at the centre of each
control's visible rect returns that control. -/
theorem view_pressable (m : TextMetrics) (s : State) (ui : UI) (w : Size) (hw : 480 ≤ w.w)
    (hh : 256 ≤ w.h) :
    ∀ t ∈ targets (layout m w (view s ui)),
      hitTest (layout m w (view s ui)) t.visible.center = some t.control := by
  rw [view_eq]
  exact hitTest_center_of_fitsIn rfl rfl (view_eq s ui ▸ view_fitsIn s ui (by omega) (by omega))

end Examples.Counter
