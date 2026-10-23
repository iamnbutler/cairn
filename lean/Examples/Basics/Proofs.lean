import Examples.Basics
import Cairn.Layout
import Cairn.Frame.Layout
import Cairn.Claims.Deliver

/-! # Basics: theorems about the view, the frame and the runtime

The moves' own evidence (`sound`), the invariant ^105 and the flows ^107–^109 are checked where
they are declared, in `Examples.Basics`. This file adds what depends on the view and layout. -/

namespace Examples.Basics
open Cairn Cairn.Claims Cairn.Layout Cairn.Runtime

/-! ## The view's controls -/

theorem controlsList_map (f : Item → Node) : ∀ xs : List Item,
    Node.controlsList (xs.map f) = xs.flatMap fun x => (f x).controls
  | [] => rfl
  | x :: xs => by simp only [List.map_cons, Node.controlsList, List.flatMap_cons, controlsList_map f xs]

theorem itemRow_refs (ui : UI) (it : Item) :
    (itemRow ui it).controls.map (·.ref) = [toggleRef it.id, deleteRef it.id] := by
  unfold itemRow
  cases it.done <;> simp [Node.controls, Node.controlsList]

/-- The view's controls, in paint order: the field, Add, then each item's checkbox and delete
button. -/
theorem view_refs (s : State) (ui : UI) :
    (view s ui).controls.map (·.ref) =
      fieldRef :: addRef :: s.items.flatMap fun it => [toggleRef it.id, deleteRef it.id] := by
  simp only [view, inputRow, heading, intro, Node.controls, Node.controlsList, controlsList_map,
    Option.toList, List.map_flatMap, itemRow_refs, List.nil_append, List.append_nil,
    List.cons_append, List.map_cons]

theorem has_iff (s : State) (k : Nat) : has s k = true ↔ ∃ it ∈ s.items, it.id = k := by
  simp [has]

/-- **Presence of ^104#k** in the view: item `k`'s delete button is there exactly when item `k`
exists, which is when the move is enabled. -/
theorem delete_present_iff (s : State) (ui : UI) (k : Nat) :
    deleteRef k ∈ (view s ui).controls.map (·.ref) ↔ deleteItem.enabled s k = true := by
  show _ ↔ has s k = true
  rw [view_refs, has_iff]
  simp [fieldRef, addRef, toggleRef, deleteRef, eq_comm]

/-- The same for ^103#k, the checkbox. -/
theorem toggle_present_iff (s : State) (ui : UI) (k : Nat) :
    toggleRef k ∈ (view s ui).controls.map (·.ref) ↔ toggleItem.enabled s k = true := by
  show _ ↔ has s k = true
  rw [view_refs, has_iff]
  simp [fieldRef, addRef, toggleRef, deleteRef, eq_comm]

/-- **Presence through layout and the frame**: in the accessibility tree of the frame, for any
metrics and window size, `^104#k` is there exactly when item `k` exists. -/
theorem delete_in_frame_iff (s : State) (ui ui' : UI) (m : TextMetrics) (w : Size) (k : Nat) :
    deleteRef k ∈ (Frame.ofLaid ui' (layout m w (view s ui))).ax.toList.filterMap AxNode.control ↔
      deleteItem.enabled s k = true := by
  rw [Frame.controls_ofLaid_layout]; exact delete_present_iff s ui k

/-- …and in every frame the running app shows (the runtime lays out `view` with the config's
layout, which is `layout` unless a test swaps it). -/
theorem delete_on_screen_iff (cfg : Config) (h : cfg.layout = layout) (st : Runtime.State State)
    (ui : UI) (hl : st.laid = relayout app cfg st.app ui) (k : Nat) :
    deleteRef k ∈ (Frame.ofLaid st.ui st.laid).ax.toList.filterMap AxNode.control ↔
      deleteItem.enabled st.app k = true := by
  rw [hl, relayout, h]; exact delete_in_frame_iff st.app ui st.ui cfg.metrics ui.size k

/-! ## Blank text adds nothing -/

/-- **Add with blank text changes nothing** (and emits nothing). -/
theorem add_blank (s : State) (h : trimmed s.field.text = []) :
    machine.update s (.press addRef) = (s, []) := by
  show (add s, []) = (s, [])
  simp only [add, h, ↓reduceIte]

/-- …and neither does Enter in the field. -/
theorem submit_blank (s : State) (h : trimmed s.field.text = []) :
    machine.update s (.submit fieldRef) = (s, []) := by
  show (add s, []) = (s, [])
  simp only [add, h, ↓reduceIte]

/-- Add with text appends exactly one item, the trimmed text, and clears the field. -/
theorem add_text (s : State) (h : trimmed s.field.text ≠ []) :
    (machine.update s (.press addRef)).1.items =
      s.items ++ [{ id := s.nextId, text := String.ofList (trimmed s.field.text) }] ∧
    (machine.update s (.press addRef)).1.field.text = [] := by
  have := add_added s
  unfold Added at this
  simp only [h, ↓reduceIte] at this
  exact this

/-! ## Items left -/

/-- **The footer counts the items not done**, in every state the machine can reach. -/
theorem footer_reachable {s : State} (h : machine.Reachable s) :
    footer s = leftLabel (undone s.items) := by
  rw [footer, (itemsLeft.reachable s h).1]

/-- …and so in every state the running app reaches, whatever events arrive. -/
theorem footer_on_screen (cfg : Config) (size : Size) (scale : Nat) (es : List Event) :
    let st := (steps app cfg (start app cfg size scale) es).1.app
    footer st = leftLabel (undone st.items) :=
  footer_reachable (steps_reachable machine [.window 106 "Basics" view] claimInfos cfg size scale es)

/-! ## Pressable, for a concrete state -/

/-- Three items, one done, in the default 480×600 window, with the field focused. -/
def three : State :=
  { items := [{ id := 1, text := "milk", done := true }, { id := 2, text := "eggs" },
              { id := 3, text := "bread" }],
    nextId := 4, left := 2 }

def threeUI : UI := { size := ⟨480, 600⟩, focus := some fieldRef }

/-- **Every control is pressable at its centre** in that state (mono metrics): the hit test at
the centre of each control's visible rect returns that control. The kernel evaluates the
layout and `checkPressable`; `hitTest_center_of_check` turns that into the theorem. -/
theorem three_pressable :
    ∀ t ∈ targets (layout TextMetrics.mono threeUI.size (view three threeUI)),
      hitTest (layout TextMetrics.mono threeUI.size (view three threeUI)) t.visible.center =
        some t.control :=
  hitTest_center_of_check (by decide +kernel)

end Examples.Basics
