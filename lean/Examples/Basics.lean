import Cairn.App
import Cairn.Text.Field
import Cairn.Text.Host
import Cairn.Layout.Core
import Cairn.Runtime.Abi
import Cairn.Frame.Boundary

/-! # Basics: the first app on the v1 ABI

A heading, a text field, an Add button, a list of items (each with a checkbox and a delete
button) and a footer counting the items left. Plain functional Lean: `init`, `view`, `update`
and `claims`, with the claims listed by hand until the claim commands (workstream A) land.

Claims (ids 101–106, chosen clear of Counter's; a later port moves them onto `move`):

| Id | Kind | Control |
|---|---|---|
| ^101 | move | the "New item" field: edits, and Enter adds |
| ^102 | move | Add |
| ^103 | move | an item's checkbox, `^103#k` for item `k` |
| ^104 | move | an item's delete button, `^104#k` |
| ^105 | invariant | the footer counts the items not done |
| ^106 | place | the window |

Item ids start at 1, so keyed controls never use key 0. Theorems are in
`Examples.Basics.Proofs`; the host side is `host/Sources/CairnBasics`. -/

namespace Examples.Basics
open Cairn

/-- The field's placeholder and accessibility label. -/
def placeholder : String := "New item"

structure Item where
  id : Nat
  text : String
  done : Bool := false
deriving Repr, BEq, Inhabited

structure State where
  items : List Item := []
  /-- The id the next item gets. -/
  nextId : Nat := 1
  /-- How many items are not done. Kept by `update` (not recomputed by `view`); invariant
  ^105 says it is always right (`Proofs.update_inv`). -/
  left : Nat := 0
  field : Text.Field := Text.Field.empty placeholder
deriving Inhabited

/-! ## Claims -/

def fieldRef : ControlRef := ⟨101, 0⟩
def addRef : ControlRef := ⟨102, 0⟩
def toggleRef (k : Nat) : ControlRef := ⟨103, k⟩
def deleteRef (k : Nat) : ControlRef := ⟨104, k⟩

def claims : List ClaimInfo :=
  [ { id := 101, kind := .move, title := "Type a new item", place := some 106,
      does := "Type in the New item field, and press Enter.",
      sees := "The text appears in the field; Enter adds it like Add does." },
    { id := 102, kind := .move, title := "Add", place := some 106,
      does := "Press Add.",
      sees := "The field's text, trimmed, is added at the end of the list and the field is cleared. Blank text changes nothing." },
    { id := 103, kind := .move, title := "Toggle an item", place := some 106,
      does := "Press an item's checkbox.",
      sees := "The item is marked done, or not done again, and the count of items left follows." },
    { id := 104, kind := .move, title := "Delete an item", place := some 106,
      does := "Press an item's delete button.",
      sees := "The item is gone." },
    { id := 105, kind := .invariant, title := "Items left",
      does := "The footer's count equals the number of items not done, in every reachable state." },
    { id := 106, kind := .place, title := "Basics window" } ]

/-! ## Update -/

/-- Whitespace for trimming: the field never holds line breaks, so this is spaces and tabs
(and anything else `Char.isWhitespace` accepts). -/
def isBlank (c : Char) : Bool := c.isWhitespace

/-- The field's text without leading and trailing whitespace. -/
def trimmed (t : List Char) : List Char :=
  ((t.dropWhile isBlank).reverse.dropWhile isBlank).reverse

/-- Add the field's trimmed text as a new item and clear the field; nothing when it's blank. -/
def add (s : State) : State :=
  match trimmed s.field.text with
  | [] => s
  | t =>
    { s with items := s.items ++ [{ id := s.nextId, text := String.ofList t }],
             nextId := s.nextId + 1, left := s.left + 1,
             field := Text.Field.empty placeholder }

def flip (k : Nat) (i : Item) : Item := if i.id = k then { i with done := !i.done } else i

def toggle (k : Nat) (s : State) : State :=
  match s.items.find? (·.id = k) with
  | none => s
  | some it =>
    { s with items := s.items.map (flip k), left := if it.done then s.left + 1 else s.left - 1 }

def delete (k : Nat) (s : State) : State :=
  match s.items.find? (·.id = k) with
  | none => s
  | some it =>
    { s with items := s.items.filter (·.id ≠ k), left := if it.done then s.left else s.left - 1 }

def update (s : State) : Action → State × List Effect
  | .edit c op =>
    if c = fieldRef then
      let (f, effs) := Text.Field.apply op s.field
      ({ s with field := f }, effs)
    else (s, [])
  | .submit c => (if c = fieldRef then add s else s, [])
  | .press c =>
    (if c = addRef then add s
     else if c.claim = 103 then toggle c.key s
     else if c.claim = 104 then delete c.key s
     else s, [])
  | _ => (s, [])

/-! ## View -/

def bg : Color := ⟨246, 246, 248, 255⟩
def ink : Color := ⟨28, 28, 30, 255⟩
def muted : Color := ⟨120, 120, 128, 255⟩
def accent : Color := ⟨0, 122, 255, 255⟩
def accentDark : Color := ⟨0, 96, 214, 255⟩
def line : Color := ⟨206, 206, 212, 255⟩
def white : Color := ⟨255, 255, 255, 255⟩

def body : Font := { size := 15 }

/-- A focus ring when `r` has keyboard focus. -/
def ring (ui : UI) (r : ControlRef) (otherwise : Option Border := none) : Option Border :=
  if ui.focus = some r then some ⟨2, accent⟩ else otherwise

def leftLabel (n : Nat) : String := if n = 1 then "1 item left" else s!"{n} items left"

def heading : Node := .text { font := { size := 22, weight := 700 }, color := ink } "Basics"

def inputRow (s : State) (ui : UI) : Node :=
  .box { axis := .row, width := .fill, gap := 8, align := .center } none
    [ .field { width := .fill, padding := ⟨6, 8, 6, 8⟩, background := some white, radius := 6,
               border := ring ui fieldRef (some ⟨1, line⟩) }
        { font := body, color := ink }
        { ref := fieldRef, role := .textField, label := placeholder }
        (s.field.view (ui.focus = some fieldRef)),
      .box { padding := ⟨6, 16, 6, 16⟩, radius := 6, border := ring ui addRef,
             background := some (if ui.hover = some addRef then accentDark else accent) }
        (some { ref := addRef, label := "Add" })
        [.text { font := { body with weight := 600 }, color := white } "Add"] ]

def itemRow (ui : UI) (it : Item) : Node :=
  .box { axis := .row, width := .fill, height := .fixed 36, gap := 10, align := .center,
         padding := ⟨0, 8, 0, 10⟩, background := some white, radius := 6 } none
    [ .box { width := .fixed 18, height := .fixed 18, radius := 4, align := .center,
             justify := .center,
             background := some (if it.done then accent else white),
             border := ring ui (toggleRef it.id) (if it.done then none else some ⟨1, line⟩) }
        (some { ref := toggleRef it.id, role := .checkbox, label := it.text,
                checked := some it.done })
        (if it.done then [.text { font := { size := 12, weight := 700 }, color := white } "✓"]
         else []),
      .text { font := body, color := if it.done then muted else ink } it.text,
      .box { width := .fill } none [],
      .box { padding := ⟨3, 8, 3, 8⟩, radius := 4, border := ring ui (deleteRef it.id),
             background := some (if ui.hover = some (deleteRef it.id) then ⟨255, 226, 226, 255⟩
                                 else ⟨240, 240, 242, 255⟩) }
        (some { ref := deleteRef it.id, label := s!"Delete {it.text}" })
        [.text { font := { size := 13 }, color := ⟨200, 40, 40, 255⟩ } "Delete"] ]

def footer (s : State) : String := leftLabel s.left

def view (s : State) (ui : UI) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨20, 20, 20, 20⟩, gap := 12,
         background := some bg, clip := true } none
    [ heading,
      inputRow s ui,
      .box { width := .fill, gap := 4 } none (s.items.map (itemRow ui)),
      .text { font := { size := 13 }, color := muted } (footer s) ]

def app : App State := { init := {}, view, update, claims }

/-! ## The app ABI (docs/runtime.md) -/

/-- Core Text metrics in the running app (the Swift host links `cairn_text_metrics`). -/
def cfg : Runtime.Config := { metrics := TextMetrics.host }

@[export cairn_app_init]
def appInit (w h scalePercent : UInt32) : Runtime.State State :=
  Runtime.initState app cfg w h scalePercent

@[export cairn_app_step]
def appStep (s : Runtime.State State) (events : ByteArray) : Runtime.State State :=
  Runtime.stepBytes app cfg Frame.boundary s events

@[export cairn_app_frame]
def appFrame (s : Runtime.State State) : ByteArray := Runtime.frameBytes Frame.boundary s

/-! ## Checks (mono metrics: the interpreter can't call the host) -/

namespace Tests
open Runtime

def tcfg : Config := {}
def run (es : List Event) : Runtime.State State := (steps app tcfg (start app tcfg ⟨480, 600⟩) es).1
def st (es : List Event) : State := (run es).app
def ui (es : List Event) : UI := (run es).ui
def texts (s : State) : List (Nat × String × Bool) := s.items.map fun i => (i.id, i.text, i.done)

/-- The centre of the control `r` on screen. -/
def at? (rs : Runtime.State State) (r : ControlRef) : Option Point :=
  (find rs.laid r).map (·.visible.center)
def clickOn (rs : Runtime.State State) (r : ControlRef) : List Event :=
  match at? rs r with
  | some p => [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}]
  | none => []

/-- Click the field, type, press Enter; then the same with Add. -/
def typed : List Event :=
  clickOn (run []) fieldRef ++ [.insertText "  milk ", .key .enter {}, .insertText "eggs"]
def two : List Event := typed ++ clickOn (run typed) addRef

#guard texts (st typed) == [(1, "milk", false)]
#guard (st typed).field.textString == "eggs"
#guard (ui typed).focus == some fieldRef
#guard texts (st two) == [(1, "milk", false), (2, "eggs", false)]
#guard (st two).field.textString == "" && (ui two).focus == none
#guard footer (st two) == "2 items left"
-- Blank text adds nothing, by Enter or by Add.
#guard texts (st (two ++ clickOn (run two) fieldRef ++ [.insertText "   ", .key .enter {}])) ==
  texts (st two)
-- Toggle item 1, then delete item 2.
def toggled : List Event := two ++ clickOn (run two) (toggleRef 1)
#guard texts (st toggled) == [(1, "milk", true), (2, "eggs", false)]
#guard footer (st toggled) == "1 item left"
def deleted : List Event := toggled ++ clickOn (run toggled) (deleteRef 2)
#guard texts (st deleted) == [(1, "milk", true)]
#guard footer (st deleted) == "0 items left"
-- Tab order: field, Add, then each item's checkbox and delete button.
#guard (tabOrder (run two).laid).map (·.ref) ==
  [fieldRef, addRef, toggleRef 1, deleteRef 1, toggleRef 2, deleteRef 2]
-- Space on a focused checkbox toggles it.
#guard texts (st (two ++ [.key .tab {}, .key .tab {}, .key .tab {}, .insertText " "])) ==
  [(1, "milk", true), (2, "eggs", false)]
-- The frame through the v1 boundary carries the keyed controls.
#guard ((decodeFrame (frameBytes Frame.boundary (run two))).map fun f =>
  f.ax.toList.filterMap (·.control)) ==
  some [fieldRef, addRef, toggleRef 1, deleteRef 1, toggleRef 2, deleteRef 2]

end Tests
end Examples.Basics
