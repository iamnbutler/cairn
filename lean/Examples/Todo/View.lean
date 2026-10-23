module

public import Examples.Todo.Model
public import Cairn.App
public import Cairn.Layout.Facts

/-! # TodoMVC: the view

The view is *rigid*: every box and field is `fixed` or `fill` on both axes, and every string
sits in a box that clips and holds only text. So no rect depends on how wide a string is, and
`Cairn.Layout.FitsIn` proves every control pressable for every state and every text metrics
whenever the window is at least `minWidth` wide and `height s` tall (`Examples.Todo.Proofs`).

Controls, by claim:

| Ref | Control |
|---|---|
| `^202` | the new-todo field |
| `^203` | toggle all ("Mark all as complete"), when there are todos |
| `^204#k` | todo `k`'s checkbox |
| `^205#k` | todo `k`'s title (double-click to edit) |
| `^206#k` | todo `k`'s delete button: always in the tree, its glyph drawn while the row is hovered or the button has focus |
| `^207#k` | todo `k`'s edit field, in edit mode (instead of the three above) |
| `^208`–`^210` | the filters All, Active, Completed, when there are todos |
| `^211` | Clear completed, when some todo is completed | -/

@[expose] public section

namespace Examples.Todo
open Cairn

def newRef : ControlRef := ⟨202, 0⟩
def toggleAllRef : ControlRef := ⟨203, 0⟩
def toggleRef (k : Nat) : ControlRef := ⟨204, k⟩
def titleRef (k : Nat) : ControlRef := ⟨205, k⟩
def deleteRef (k : Nat) : ControlRef := ⟨206, k⟩
def editRef (k : Nat) : ControlRef := ⟨207, k⟩
def filterRef : Filter → ControlRef
  | .all => ⟨208, 0⟩
  | .active => ⟨209, 0⟩
  | .completed => ⟨210, 0⟩
def clearRef : ControlRef := ⟨211, 0⟩

/-! ## Sizes (logical points) -/

def pad : Nat := 16
def headH : Nat := 56
def headerH : Nat := 48
def rowH : Nat := 44
def footH : Nat := 40
def infoH : Nat := 28
def boxW : Nat := 44
def filterW : Nat := 76
def clearW : Nat := 128

/-- The narrowest window the view fits: padding, the footer's fixed boxes, and one point for the
counter. Every row needs less. -/
def minWidth : Nat := 2 * pad + 3 * filterW + clearW + 1

/-- The height the view needs: the header, one row per listed todo, the footer when there are
todos, and the info line. There is no scrolling, so a window must be at least this tall for
every todo to be on screen. -/
def height (s : State) : Nat :=
  2 * pad + headH + headerH + (if s.todos.isEmpty then 0 else rowH * (visible s).length + footH) +
    infoH

def initialHeight : Nat := 2 * pad + headH + headerH + infoH

/-! ## Look -/

def bg : Color := ⟨245, 245, 245, 255⟩
def white : Color := ⟨255, 255, 255, 255⟩
def ink : Color := ⟨72, 72, 72, 255⟩
def muted : Color := ⟨170, 170, 170, 255⟩
def faint : Color := ⟨215, 215, 215, 255⟩
def brand : Color := ⟨184, 63, 69, 255⟩
def accent : Color := ⟨0, 122, 255, 255⟩
def danger : Color := ⟨193, 72, 72, 255⟩

def body : Font := { size := 18, weight := 300 }
def small : Font := { size := 13 }

/-- A focus ring when `r` has keyboard focus. -/
def ring (ui : UI) (r : ControlRef) (otherwise : Option Border := none) : Option Border :=
  if ui.focus = some r then some ⟨2, accent⟩ else otherwise

/-- A box of fixed width and full height that clips its text, centred. -/
def cell (w : Sizing) (ctl : Option Control) (kids : List Node) (bgc : Option Color := none)
    (border : Option Border := none) (justify : Align := .center) (padding : Insets := {}) :
    Node :=
  .box { width := w, height := .fill, clip := true, align := .center, justify, axis := .row,
         background := bgc, border, radius := 3, padding } ctl kids

def spacer (w : Nat) : Node := cell (.fixed w) none []

/-- The counter text (T34, T35): "item" exactly when one todo is active. -/
def itemsWord (n : Nat) : String := if n = 1 then " item left" else " items left"

/-! ## Rows -/

/-- Todo `k`'s row is hot: the pointer is over one of its controls, or its delete button has
keyboard focus. The delete glyph is drawn only then (T21, T49). -/
def hot (ui : UI) (k : Nat) : Bool :=
  decide (ui.hover = some (toggleRef k)) || decide (ui.hover = some (titleRef k)) ||
    decide (ui.hover = some (deleteRef k)) || decide (ui.focus = some (deleteRef k))

/-- A todo's row: checkbox, title and delete button, or in edit mode the edit field (T18, T25). -/
def todoRow (s : State) (ui : UI) (t : Todo) : Node :=
  match s.editing with
  | some e =>
    if e.id = t.id then
      .box { axis := .row, width := .fill, height := .fixed rowH, background := some white } none
        [ spacer boxW,
          .field { width := .fill, height := .fill, padding := ⟨0, 12, 0, 12⟩,
                   background := some white, border := some ⟨1, accent⟩ }
            { font := body, color := ink }
            { ref := editRef t.id, role := .textField, label := t.title }
            (e.field.view (ui.focus = some (editRef t.id))) ]
    else viewRow ui t
  | none => viewRow ui t
where
  viewRow (ui : UI) (t : Todo) : Node :=
    .box { axis := .row, width := .fill, height := .fixed rowH, background := some white } none
      [ cell (.fixed boxW)
          (some { ref := toggleRef t.id, role := .checkbox, label := t.title,
                  checked := some t.completed })
          [.text { font := body, color := if t.completed then ⟨93, 194, 175, 255⟩ else faint }
            (if t.completed then "✓" else "○")]
          (border := ring ui (toggleRef t.id)),
        cell .fill (some { ref := titleRef t.id, role := .text, label := t.title })
          [.text { font := body, color := if t.completed then muted else ink } t.title]
          (justify := .start),
        cell (.fixed boxW) (some { ref := deleteRef t.id, label := s!"Delete {t.title}" })
          (if hot ui t.id then [.text { font := body, color := danger } "×"] else [])
          (border := ring ui (deleteRef t.id)) ]

/-! ## The view -/

def heading : Node :=
  .box { width := .fill, height := .fixed headH, clip := true, align := .center,
         justify := .center } none
    [.text { font := { size := 48, weight := 200 }, color := brand } "todos"]

/-- The header: toggle all (when there are todos, T14) and the new-todo field (T3). -/
def header (s : State) (ui : UI) : Node :=
  .box { axis := .row, width := .fill, height := .fixed headerH, background := some white } none
    [ if s.todos.isEmpty then spacer boxW
      else cell (.fixed boxW)
        (some { ref := toggleAllRef, role := .checkbox, label := "Mark all as complete",
                checked := some (allDone s) })
        [.text { font := body, color := if allDone s then ink else faint } "❯"]
        (border := ring ui toggleAllRef),
      .field { width := .fill, height := .fill, padding := ⟨0, 12, 0, 12⟩,
               background := some white, border := ring ui newRef }
        { font := body, color := ink }
        { ref := newRef, role := .textField, label := newPlaceholder }
        (s.newField.view (ui.focus = some newRef)) ]

/-- The listed todos, one fixed-height row each (T40). -/
def list (s : State) (ui : UI) : Node :=
  .box { width := .fill, height := .fixed (rowH * (visible s).length) } none
    ((visible s).map (todoRow s ui))

def filterBox (s : State) (ui : UI) (f : Filter) : Node :=
  cell (.fixed filterW)
    (some { ref := filterRef f, role := .tab, label := f.label, selected := s.filter = f })
    [.text { font := small, color := ink } f.label]
    (border := ring ui (filterRef f)
      (if s.filter = f then some ⟨1, ⟨219, 180, 180, 255⟩⟩ else none))

/-- The footer: the counter with its number in bold (T34–T36), the filters (T39, T41) and
Clear completed when some todo is completed (T37). -/
def footer (s : State) (ui : UI) : Node :=
  .box { axis := .row, width := .fill, height := .fixed footH, background := some white } none
    [ cell .fill none
        [.text { font := { small with weight := 700 }, color := ink } (toString s.left),
         .text { font := small, color := ink } (itemsWord s.left)]
        (justify := .start) (padding := ⟨0, 0, 0, 14⟩),
      filterBox s ui .all, filterBox s ui .active, filterBox s ui .completed,
      if anyDone s then
        cell (.fixed clearW) (some { ref := clearRef, label := "Clear completed" })
          [.text { font := small, color := ink } "Clear completed"]
          (border := ring ui clearRef)
      else spacer clearW ]

def info : Node :=
  .box { width := .fill, height := .fixed infoH, clip := true, align := .center,
         justify := .center } none
    [.text { font := { size := 11 }, color := muted } "Double-click to edit a todo"]

/-- The whole window. With no todos, only the header and the info line (T1, T2, T4). -/
def view (s : State) (ui : UI) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨pad, pad, pad, pad⟩, background := some bg }
    none
    ([heading, header s ui] ++ (if s.todos.isEmpty then [] else [list s ui, footer s ui]) ++ [info])

/-! ## The listed rows -/

/-- The todo a control belongs to, if it marks a row: a checkbox, or an edit field. -/
def rowKey (c : Control) : Option Nat :=
  if c.ref.claim = 204 ∨ c.ref.claim = 207 then some c.ref.key else none

theorem controlsList_map {α : Type} (f : α → Node) : ∀ xs : List α,
    Node.controlsList (xs.map f) = xs.flatMap fun x => (f x).controls
  | [] => rfl
  | x :: xs => by
    simp only [List.map_cons, Node.controlsList, List.flatMap_cons, controlsList_map f xs]

theorem controlsList_append (xs ys : List Node) :
    Node.controlsList (xs ++ ys) = Node.controlsList xs ++ Node.controlsList ys := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simp only [List.cons_append, Node.controlsList, ih, List.append_assoc]

/-- Each row contributes exactly its todo's id. -/
theorem todoRow_rowKeys (s : State) (ui : UI) (t : Todo) :
    (todoRow s ui t).controls.filterMap rowKey = [t.id] := by
  unfold todoRow
  have hv : (todoRow.viewRow ui t).controls.filterMap rowKey = [t.id] := by
    simp only [todoRow.viewRow, cell, Node.controls, Node.controlsList, Option.toList,
      List.nil_append, List.append_nil, List.cons_append, List.filterMap_cons, rowKey, toggleRef,
      titleRef, deleteRef, List.filterMap_nil]
    cases t.completed <;> cases hot ui t.id <;> simp [Node.controls, Node.controlsList]
  split
  · split
    · simp [spacer, cell, Node.controls, Node.controlsList, rowKey, editRef]
    · exact hv
  · exact hv

/-- The header and footer contribute no row keys. -/
theorem header_rowKeys (s : State) (ui : UI) : (header s ui).controls.filterMap rowKey = [] := by
  unfold header
  cases s.todos.isEmpty <;>
    simp [spacer, cell, Node.controls, Node.controlsList, rowKey, toggleAllRef, newRef]

theorem footer_rowKeys (s : State) (ui : UI) : (footer s ui).controls.filterMap rowKey = [] := by
  unfold footer
  cases anyDone s <;>
    simp [spacer, cell, filterBox, Node.controls, Node.controlsList, rowKey, filterRef, clearRef]

/-- **The listed rows are the filtered todos** (T40): in every state, under any interaction
state, the rows the view shows are exactly the todos the filter accepts, in creation order. -/
theorem view_rows (s : State) (ui : UI) :
    (view s ui).controls.filterMap rowKey = (visible s).map (·.id) := by
  have hl : (list s ui).controls.filterMap rowKey = (visible s).map (·.id) := by
    simp only [list, Node.controls, Option.toList, List.nil_append, controlsList_map,
      List.filterMap_flatMap, todoRow_rowKeys]
    induction visible s with
    | nil => rfl
    | cons t ts ih => simp only [List.flatMap_cons, ih, List.map_cons, List.singleton_append]
  unfold view
  cases h : s.todos.isEmpty
  · simp only [Node.controls, Option.toList, List.nil_append, controlsList_append,
      Node.controlsList, List.filterMap_append, header_rowKeys, footer_rowKeys, hl, heading, info,
      Bool.false_eq_true, ↓reduceIte, List.cons_append, List.singleton_append, List.append_nil,
      List.filterMap_nil, List.nil_append]
  · have : visible s = [] := by
      simp only [visible, List.isEmpty_iff.1 h, List.filter_nil]
    simp only [Node.controls, Option.toList, List.nil_append, controlsList_append,
      Node.controlsList, List.filterMap_append, header_rowKeys, heading, info, ↓reduceIte,
      List.cons_append, List.singleton_append, List.append_nil, List.filterMap_nil, this,
      List.map_nil]

end Examples.Todo
