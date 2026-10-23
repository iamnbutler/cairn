import Cairn.Frame
import Cairn.App

/-! `Frame.ofLaid`: a laid-out tree becomes what crosses the boundary: draw commands in paint
order, the accessibility tree, and the focused field's text-input state.

* **Paint order** (back to front, depth first). A box paints its background and border (one
  `rect`, only when it has either), then its children, wrapped in `pushClip`/`popClip` of its
  rect when it clips. Text paints one `text` at its baseline origin. A field paints its
  background and border, then, clipped to its rect, its selection rects, its text (or its
  placeholder at half alpha when the text is empty), and its caret when focused and the selection
  is empty.
* **Accessibility.** One `AxNode` per control (boxes with a control, fields) and per text, in
  paint order, each with its visible rect (`rect ∩ clip`). A node's parent is the nearest
  enclosing control. A field's value is its text and its role is `textField`.
* **Text input** describes the first field whose control has focus.

Focus comes from the runtime (`UI.focus`), the one source of truth; `FieldView.focused` is for the
view's own styling and is not read here. `Laid.text`'s `baseline` is absolute (window y).

Theorems: `controls_ofLaid` (the accessibility tree's controls are exactly the laid tree's, in
order, which is how presence reaches the accessibility mirror), `mem_ax_ofLaid`,
`ax_refs_nodup` (distinct refs in the tree give distinct refs in the mirror), `parent_lt_ofLaid`
(every parent index points at an earlier node) and `balanced_ofLaid` (clips are balanced). -/

namespace Cairn

namespace Frame

/-- Selection highlight: the macOS accent blue at 30%. -/
def selectionColor : Color := ⟨0, 122, 255, 77⟩

def boxDraws (r : Rect) (s : Style) : List Draw :=
  if s.background.isSome || s.border.isSome then [.rect r s.background s.radius s.border] else []

def halfAlpha (c : Color) : Color := { c with a := c.a / 2 }

/-- What a field paints inside its clip. -/
def fieldDraws (focus : Option ControlRef) (ts : TextStyle) (c : Control) (v : FieldView)
    (origin : Point) (caret : Rect) (sel : List Rect) : List Draw :=
  sel.map (fun s => .rect s (some selectionColor) 0 none) ++
    (if v.text.isEmpty then
      (if v.placeholder.isEmpty then [] else [.text origin ts.font (halfAlpha ts.color) v.placeholder])
    else [.text origin ts.font ts.color v.text]) ++
    (if focus == some c.ref && v.anchor == v.caret then [.rect caret (some ts.color) 0 none] else [])

mutual
/-- Draw commands for a laid tree, back to front. -/
def paint (focus : Option ControlRef) : Laid → List Draw
  | .box r _ s _ kids =>
    boxDraws r s ++
      (if s.clip then .pushClip r :: (paintAll focus kids ++ [.popClip]) else paintAll focus kids)
  | .text r _ baseline ts content => [.text ⟨r.x, baseline⟩ ts.font ts.color content]
  | .field r _ s ts c v origin caret sel =>
    boxDraws r s ++ .pushClip r :: (fieldDraws focus ts c v origin caret sel ++ [.popClip])

def paintAll (focus : Option ControlRef) : List Laid → List Draw
  | [] => []
  | l :: ls => paint focus l ++ paintAll focus ls
end

def controlNode (focus : Option ControlRef) (parent : Option Nat) (rect : Rect) (c : Control) :
    AxNode :=
  { control := some c.ref, role := c.role, rect, label := c.label, value := c.value, parent,
    focused := focus == some c.ref, selected := c.selected, checked := c.checked }

mutual
/-- Append the accessibility nodes of a laid tree to `acc`; `parent` is the index of the
nearest enclosing control's node. -/
def axOf (focus : Option ControlRef) (parent : Option Nat) (acc : Array AxNode) :
    Laid → Array AxNode
  | .box r clip _ (some c) kids =>
    axAll focus (some acc.size) (acc.push (controlNode focus parent (r.inter clip) c)) kids
  | .box _ _ _ none kids => axAll focus parent acc kids
  | .text r clip _ _ content =>
    acc.push { control := none, role := .text, rect := r.inter clip, label := content, parent }
  | .field r clip _ _ c v .. =>
    acc.push { controlNode focus parent (r.inter clip) c with role := .textField, value := v.text }

def axAll (focus : Option ControlRef) (parent : Option Nat) (acc : Array AxNode) :
    List Laid → Array AxNode
  | [] => acc
  | l :: ls => axAll focus parent (axOf focus parent acc l) ls
end

mutual
/-- The text-input state of the first focused field. -/
def textInputOf (focus : Option ControlRef) : Laid → Option TextInput
  | .box _ _ _ _ kids => textInputAll focus kids
  | .text .. => none
  | .field r _ _ _ c v origin caret _ =>
    if focus == some c.ref then
      some { control := c.ref, rect := r, caret, text := v.text, textOrigin := origin,
             selection := (min v.anchor v.caret, max v.anchor v.caret), marked := v.marked }
    else none

def textInputAll (focus : Option ControlRef) : List Laid → Option TextInput
  | [] => none
  | l :: ls => (textInputOf focus l).orElse fun _ => textInputAll focus ls
end

/-- The frame for a laid tree. The runtime fills in `cursor` and `effects`. -/
def ofLaid (ui : UI) (l : Laid) : Frame where
  size := ui.size
  draws := (paint ui.focus l).toArray
  ax := axOf ui.focus none #[] l
  textInput := textInputOf ui.focus l

end Frame

namespace Laid

mutual
/-- The controls of a laid tree, in paint order. -/
def controls : Laid → List Control
  | .box _ _ _ c kids => c.toList ++ controlsAll kids
  | .text .. => []
  | .field _ _ _ _ c .. => [c]

def controlsAll : List Laid → List Control
  | [] => []
  | l :: ls => controls l ++ controlsAll ls
end

end Laid

namespace Frame

/-! ## The accessibility tree has exactly the laid tree's controls -/

mutual
theorem axOf_controls (focus : Option ControlRef) (parent : Option Nat) (acc : Array AxNode)
    (l : Laid) : (axOf focus parent acc l).toList.filterMap AxNode.control =
      acc.toList.filterMap AxNode.control ++ (l.controls).map Control.ref := by
  match l with
  | .box r clip s (some c) kids =>
    rw [axOf, axAll_controls]
    simp [Laid.controls, controlNode]
  | .box _ _ _ none kids =>
    rw [axOf, axAll_controls]
    simp [Laid.controls]
  | .text .. => simp [axOf, Laid.controls]
  | .field .. => simp [axOf, Laid.controls, controlNode]

theorem axAll_controls (focus : Option ControlRef) (parent : Option Nat) (acc : Array AxNode)
    (ls : List Laid) : (axAll focus parent acc ls).toList.filterMap AxNode.control =
      acc.toList.filterMap AxNode.control ++ (Laid.controlsAll ls).map Control.ref := by
  match ls with
  | [] => simp [axAll, Laid.controlsAll]
  | l :: ls =>
    rw [axAll, axAll_controls, axOf_controls]
    simp [Laid.controlsAll]
end

/-- **Presence reaches accessibility.** The controls in the frame's accessibility tree are
exactly the controls of the laid tree, in order. -/
theorem controls_ofLaid (ui : UI) (l : Laid) :
    (ofLaid ui l).ax.toList.filterMap AxNode.control = l.controls.map Control.ref := by
  simp [ofLaid, axOf_controls]

/-- A claim's control is in the accessibility tree iff it is in the laid tree. -/
theorem mem_ax_ofLaid (ui : UI) (l : Laid) (c : ControlRef) :
    (∃ n ∈ (ofLaid ui l).ax, n.control = some c) ↔ ∃ k ∈ l.controls, k.ref = c := by
  have h := congrArg (c ∈ ·) (controls_ofLaid ui l)
  simp only [List.mem_filterMap, List.mem_map, Array.mem_toList_iff] at h
  exact Iff.of_eq h

/-- **One node per control.** If the laid tree's controls have pairwise distinct refs (an app
invariant), so do the accessibility nodes': the host may key its elements by `ControlRef`. -/
theorem ax_refs_nodup (ui : UI) (l : Laid) (h : (l.controls.map Control.ref).Nodup) :
    ((ofLaid ui l).ax.toList.filterMap AxNode.control).Nodup := by
  rw [controls_ofLaid]; exact h

/-! ## Parents point backwards -/

/-- Every node's parent is an earlier node. -/
def ParentsOk (ax : Array AxNode) : Prop :=
  ∀ i (h : i < ax.size) p, ax[i].parent = some p → p < i

def ParentBelow (parent : Option Nat) (n : Nat) : Prop := ∀ p, parent = some p → p < n

theorem ParentsOk.push {ax : Array AxNode} {n : AxNode} (h : ParentsOk ax)
    (hn : ParentBelow n.parent ax.size) : ParentsOk (ax.push n) := by
  intro i hi p hp
  rw [Array.size_push] at hi
  by_cases hlt : i < ax.size
  · rw [Array.getElem_push_lt hlt] at hp
    exact h i hlt p hp
  · have : i = ax.size := by omega
    subst this
    rw [Array.getElem_push_eq] at hp
    exact hn p hp

mutual
theorem axOf_size (focus : Option ControlRef) (parent : Option Nat) (acc : Array AxNode)
    (l : Laid) : acc.size ≤ (axOf focus parent acc l).size := by
  match l with
  | .box r clip s (some c) kids =>
    rw [axOf]; exact Nat.le_trans (by simp) (axAll_size _ _ _ _)
  | .box _ _ _ none kids => rw [axOf]; exact axAll_size ..
  | .text .. => simp [axOf]
  | .field .. => simp [axOf]

theorem axAll_size (focus : Option ControlRef) (parent : Option Nat) (acc : Array AxNode)
    (ls : List Laid) : acc.size ≤ (axAll focus parent acc ls).size := by
  match ls with
  | [] => simp [axAll]
  | l :: ls =>
    rw [axAll]
    exact Nat.le_trans (axOf_size focus parent acc l) (axAll_size ..)
end

theorem ParentBelow.mono {p : Option Nat} {n m : Nat} (h : ParentBelow p n) (hm : n ≤ m) :
    ParentBelow p m := fun q hq => Nat.lt_of_lt_of_le (h q hq) hm

mutual
theorem axOf_parents (focus : Option ControlRef) (parent : Option Nat) (acc : Array AxNode)
    (l : Laid) (h : ParentsOk acc) (hp : ParentBelow parent acc.size) :
    ParentsOk (axOf focus parent acc l) := by
  match l with
  | .box r clip s (some c) kids =>
    rw [axOf]
    apply axAll_parents
    · exact h.push hp
    · intro q hq; simp at hq; simp [hq]
  | .box _ _ _ none kids => rw [axOf]; exact axAll_parents _ _ _ _ h hp
  | .text .. => exact h.push hp
  | .field .. => exact h.push hp

theorem axAll_parents (focus : Option ControlRef) (parent : Option Nat) (acc : Array AxNode)
    (ls : List Laid) (h : ParentsOk acc) (hp : ParentBelow parent acc.size) :
    ParentsOk (axAll focus parent acc ls) := by
  match ls with
  | [] => simpa [axAll] using h
  | l :: ls =>
    rw [axAll]
    exact axAll_parents _ _ _ _ (axOf_parents _ _ _ _ h hp) (hp.mono (axOf_size ..))
end

/-- Every accessibility node's parent comes before it, so the host can build the tree in one
pass. -/
theorem parent_lt_ofLaid (ui : UI) (l : Laid) : ParentsOk (ofLaid ui l).ax :=
  axOf_parents _ _ _ _ (fun i h => by simp at h) (fun _ h => by simp at h)

/-! ## Clips are balanced -/

/-- The clip stack depth after running `ds` from depth `d`; `none` if a `popClip` finds the
stack empty. -/
def clipDepth : Nat → List Draw → Option Nat
  | d, [] => some d
  | d, .pushClip _ :: ds => clipDepth (d + 1) ds
  | 0, .popClip :: _ => none
  | d + 1, .popClip :: ds => clipDepth d ds
  | d, .rect .. :: ds => clipDepth d ds
  | d, .text .. :: ds => clipDepth d ds

/-- Every `popClip` closes an earlier `pushClip`, and every `pushClip` is closed. -/
def Balanced (ds : List Draw) : Prop := clipDepth 0 ds = some 0

/-- Draws with no clip commands leave the depth alone. -/
def NoClip (ds : List Draw) : Prop := ∀ d ∈ ds, ∀ r, d ≠ .pushClip r ∧ d ≠ .popClip

theorem clipDepth_noClip {ds : List Draw} (h : NoClip ds) (d : Nat) (rest : List Draw) :
    clipDepth d (ds ++ rest) = clipDepth d rest := by
  induction ds with
  | nil => rfl
  | cons x xs ih =>
    have hx := h x List.mem_cons_self
    have ih := ih (fun y hy => h y (List.mem_cons_of_mem _ hy))
    cases x with
    | rect r f rad b => simpa [clipDepth] using ih
    | text o f c s => simpa [clipDepth] using ih
    | pushClip r => exact absurd rfl (hx r).1
    | popClip => exact absurd rfl (hx ⟨0, 0, 0, 0⟩).2

theorem noClip_boxDraws (r : Rect) (s : Style) : NoClip (boxDraws r s) := by
  unfold boxDraws; split <;> simp [NoClip]

theorem noClip_fieldDraws (focus : Option ControlRef) (ts : TextStyle) (c : Control)
    (v : FieldView) (o : Point) (caret : Rect) (sel : List Rect) :
    NoClip (fieldDraws focus ts c v o caret sel) := by
  unfold fieldDraws NoClip
  intro d hd r
  simp only [List.mem_append, List.mem_map] at hd
  rcases hd with (⟨s, _, rfl⟩ | hd) | hd
  · simp
  · split at hd
    · split at hd <;> simp_all
    · simp_all
  · split at hd <;> simp_all

mutual
theorem clipDepth_paint (focus : Option ControlRef) (l : Laid) (d : Nat) (rest : List Draw) :
    clipDepth d (paint focus l ++ rest) = clipDepth d rest := by
  match l with
  | .box r _ s _ kids =>
    rw [paint, List.append_assoc, clipDepth_noClip (noClip_boxDraws r s)]
    split
    · simp only [List.cons_append, List.append_assoc, clipDepth]
      rw [clipDepth_paintAll]
      rfl
    · exact clipDepth_paintAll ..
  | .text .. => rfl
  | .field r _ s ts c v o caret sel =>
    rw [paint, List.append_assoc, clipDepth_noClip (noClip_boxDraws r s)]
    simp only [List.cons_append, List.append_assoc, clipDepth]
    rw [clipDepth_noClip (noClip_fieldDraws focus ts c v o caret sel)]
    rfl

theorem clipDepth_paintAll (focus : Option ControlRef) (ls : List Laid) (d : Nat)
    (rest : List Draw) : clipDepth d (paintAll focus ls ++ rest) = clipDepth d rest := by
  match ls with
  | [] => rfl
  | l :: ls =>
    rw [paintAll, List.append_assoc, clipDepth_paint, clipDepth_paintAll]
end

/-- **Clips are balanced** in every frame `ofLaid` builds. -/
theorem balanced_ofLaid (ui : UI) (l : Laid) : Balanced (ofLaid ui l).draws.toList := by
  have := clipDepth_paint ui.focus l 0 []
  simpa [Balanced, ofLaid, clipDepth] using this

end Frame

/-! ## Examples -/

namespace Frame.Examples

private def button : Control := { ref := ⟨1, 0⟩, label := "Add" }
private def field : Control := { ref := ⟨2, 0⟩, role := .textField, label := "New todo" }
private def win : Rect := ⟨0, 0, 400, 300⟩

/-- A clipping column holding a button with a label and a focused field. -/
private def sample : Laid :=
  .box win win { clip := true, background := some ⟨255, 255, 255, 255⟩ } none [
    .box ⟨10, 10, 80, 24⟩ win { background := some ⟨0, 0, 255, 255⟩ } (some button) [
      .text ⟨20, 14, 30, 16⟩ win 27 {} "Add"],
    .field ⟨10, 40, 200, 24⟩ win {} {} field { text := "héllo", caret := 5, anchor := 2 }
      ⟨14, 57⟩ ⟨44, 44, 1, 16⟩ [⟨24, 44, 20, 16⟩]]

private def f := ofLaid { focus := some ⟨2, 0⟩ } sample

#guard f.draws.size == 9
#guard f.draws[0]! == .rect win (some ⟨255, 255, 255, 255⟩) 0 none
#guard f.draws[1]! == .pushClip win
#guard f.draws[3]! == .text ⟨20, 27⟩ {} ⟨0, 0, 0, 255⟩ "Add"
#guard f.draws.back! == .popClip
#guard f.ax.map (·.role) == #[.button, .text, .textField]
#guard f.ax.map (·.parent) == #[none, some 0, none]
#guard f.ax[2]!.value == "héllo" && f.ax[2]!.focused
#guard (f.textInput.map (·.selection)) == some (2, 5)
-- No caret while there is a selection; a caret once it collapses.
#guard !(f.draws.contains (.rect ⟨44, 44, 1, 16⟩ (some ⟨0, 0, 0, 255⟩) 0 none))
#guard (ofLaid { focus := none } sample).textInput.isNone
#guard (f.textInput.map (·.textOrigin)) == some ⟨14, 57⟩

end Frame.Examples
end Cairn
