module

public import Cairn

/-! # Fixture: Cairn's own test app

What the framework's checks need from an app, in one small window (test/fixture/README.md): a
heading and a wrapped paragraph (text, `Node.para`), a text field with Enter (editing, the text
input client), a button, a list of rows with keyed controls (hit testing, `^N#k`), a button whose
effect comes back as a message (a timer), an invariant with a runnable check, and a flow.

| Id | Kind | What |
|---|---|---|
| ^1 | place | the window |
| ^2 | move | the New item field: edits, and Enter adds |
| ^3 | move | Add |
| ^4 | move, keyed | an item's checkbox, `^4#k` for item `k` |
| ^5 | move, keyed | an item's delete button, `^5#k` |
| ^6 | move | Flash: sets a timer; the note shows until it fires |
| ^7 | invariant | item ids are positive and below the next id |
| ^8 | flow | add two items and finish one |

Its claims are `fixture^N`, in test/fixture/claims.lock. None of them is in Cairn's ledger, so
changing the fixture never moves a Cairn claim. -/

@[expose] public section

namespace Fixture
open Cairn Cairn.Claims

def placeholder : String := "New item"

structure Item where
  id : Nat
  text : String
  done : Bool := false
deriving Repr, BEq, DecidableEq, Inhabited

structure State where
  items : List Item := []
  /-- The id the next item gets. -/
  nextId : Nat := 1
  field : Text.Field := Text.Field.empty placeholder
  /-- Whether the Flash note shows: from a press of Flash until its timer fires. -/
  flash : Bool := false
deriving Repr, DecidableEq, Inhabited

def fieldRef : ControlRef := ⟨2, 0⟩
def addRef : ControlRef := ⟨3, 0⟩
def toggleRef (k : Nat) : ControlRef := ⟨4, k⟩
def deleteRef (k : Nat) : ControlRef := ⟨5, k⟩
def flashRef : ControlRef := ⟨6, 0⟩

/-- The timer Flash sets, and how long the note shows. -/
def flashTimer : String := "flash"
def flashMs : Nat := 400

/-! ## The model -/

/-- The field's text without leading and trailing whitespace. -/
def trimmed (t : List Char) : List Char :=
  ((t.dropWhile Char.isWhitespace).reverse.dropWhile Char.isWhitespace).reverse

/-- Add the field's trimmed text as a new item and clear the field; nothing when it's blank. -/
def add (s : State) : State :=
  if trimmed s.field.text = [] then s
  else
    { s with items := s.items ++ [{ id := s.nextId, text := String.ofList (trimmed s.field.text) }],
             nextId := s.nextId + 1, field := Text.Field.empty placeholder }

def has (s : State) (k : Nat) : Bool := s.items.any (·.id == k)

def flip (k : Nat) (i : Item) : Item := if i.id = k then { i with done := !i.done } else i

def toggle (k : Nat) (s : State) : State := { s with items := s.items.map (flip k) }

def delete (k : Nat) (s : State) : State := { s with items := s.items.filter (·.id ≠ k) }

def left (s : State) : Nat := (s.items.filter (!·.done)).length

/-- ^7's statement. -/
def Inv (s : State) : Prop := 0 < s.nextId ∧ ∀ i ∈ s.items, i.id < s.nextId

theorem add_inv {s : State} (h : Inv s) : Inv (add s) := by
  obtain ⟨hn, hb⟩ := h
  unfold add
  by_cases ht : trimmed s.field.text = []
  · simp only [ht, ↓reduceIte]; exact ⟨hn, hb⟩
  · simp only [ht, ↓reduceIte]
    refine ⟨Nat.succ_pos _, fun i hi => ?_⟩
    simp only [List.mem_append, List.mem_singleton] at hi
    rcases hi with hi | rfl
    · exact Nat.lt_succ_of_lt (hb i hi)
    · exact Nat.lt_succ_self _

theorem flip_id (k : Nat) (i : Item) : (flip k i).id = i.id := by
  unfold flip; split <;> rfl

theorem toggle_inv (k : Nat) {s : State} (h : Inv s) : Inv (toggle k s) := by
  obtain ⟨hn, hb⟩ := h
  refine ⟨hn, fun i hi => ?_⟩
  obtain ⟨j, hj, rfl⟩ := List.mem_map.mp hi
  rw [flip_id]; exact hb j hj

theorem delete_inv (k : Nat) {s : State} (h : Inv s) : Inv (delete k s) :=
  ⟨h.1, fun i hi => h.2 i (List.mem_filter.mp hi).1⟩

/-! ## Claims -/

place ^1 window "Fixture window" where
  does "The window: a heading, a paragraph, the New item field and Add, Flash, the items and the count left."

move ^2 typeItem (s : State) "Type a new item" in ^1 where
  does "Type in the New item field, and press Enter."
  sees "The text appears in the field; Enter adds it like Add does."
  on edit (op : TextOp)
    emit := ({ s with field := (Text.Field.apply op s.field).1 }, (Text.Field.apply op s.field).2)
    post s' := s'.field = (Text.Field.apply op s.field).1 ∧ s'.items = s.items ∧
      s'.nextId = s.nextId
    sound := by intro s op; exact ⟨rfl, rfl, rfl⟩
  on submit
    apply := add s
    post s' := s' = add s
    sound := by intro s; rfl

move ^3 addItem (s : State) "Add" in ^1 where
  does "Press Add."
  sees "The field's text, trimmed, is added at the end of the list and the field is cleared. Blank text changes nothing."
  on press
    apply := add s
    post s' := s' = add s
    sound := by intro s; rfl

move ^4 toggleItem (s : State) (k : Nat) "Toggle an item" in ^1 where
  does "Press an item's checkbox."
  sees "The item is marked done, or not done again."
  enabled := has s k
  on press
    apply := toggle k s
    post s' := s'.items = s.items.map (flip k)
    sound := by intro s k _; rfl

move ^5 deleteItem (s : State) (k : Nat) "Delete an item" in ^1 where
  does "Press an item's delete button."
  sees "The item is gone, and its checkbox and delete button with it."
  enabled := has s k
  on press
    apply := delete k s
    post s' := s'.items = s.items.filter (·.id ≠ k)
    sound := by intro s k _; rfl

move ^6 flashMove (s : State) "Flash" in ^1 where
  does "Press Flash."
  sees "A note shows, and goes when the timer the press set fires."
  on press
    emit := ({ s with flash := true }, [.setTimer flashTimer flashMs])
    post s' := s'.flash = true ∧ s'.items = s.items
    sound := by intro s; exact ⟨rfl, rfl⟩

/-- The world's messages: Flash's timer clears the note. -/
def receive (s : State) : Msg → State × List Effect
  | .timer n => (if n = flashTimer then { s with flash := false } else s, [])
  | _ => (s, [])

def machine : Machine State := { init := {}, moves := moves%, receive }

invariant ^7 idsBelow "Item ids stay below the next id" for machine where
  does "Every item's id is positive and below the id the next item gets, in every reachable state."
  holds s := Inv s
  init := ⟨Nat.one_pos, fun _ h => by simp only [machine, List.not_mem_nil] at h⟩
  step := machine.preserves <|
    Move.all_cons (typeItem.preserves _ (fun _ _ h => h) fun _ h => add_inv h)
      (Move.all_cons (addItem.preserves _ fun _ h => add_inv h)
      (Move.all_cons (toggleItem.preserves _ fun _ k _ h => toggle_inv k h)
      (Move.all_cons (deleteItem.preserves _ fun _ k _ h => delete_inv k h)
      (Move.all_cons (flashMove.preserves _ fun _ h => h) Move.all_nil))))
  receive := by
    intro s m h
    cases m with
    | timer n =>
      show Inv (if n = flashTimer then { s with flash := false } else s)
      split <;> exact h
    | _ => exact h

flow ^8 addAndFinish "Add two items and finish one" for machine where
  does "Type milk and press Enter, type eggs and press Add, then check milk."
  sees "Two items, milk done."
  goal s := s.items.map (·.text) = ["milk", "eggs"] ∧ s.items.map (·.done) = [true, false]
  witness edit ^2 (.insert "milk"), submit ^2, edit ^2 (.insert " eggs "), press ^3, press ^4#1

def claimInfos : List ClaimInfo := claims%

/-! ## View -/

def bg : Color := ⟨246, 246, 248, 255⟩
def ink : Color := ⟨28, 28, 30, 255⟩
def muted : Color := ⟨120, 120, 128, 255⟩
def accent : Color := ⟨0, 122, 255, 255⟩
def accentDark : Color := ⟨0, 96, 214, 255⟩
def line : Color := ⟨206, 206, 212, 255⟩
def white : Color := ⟨255, 255, 255, 255⟩

def body : Font := { size := 15 }

def ring (ui : UI) (r : ControlRef) (otherwise : Option Border := none) : Option Border :=
  if ui.focus = some r then some ⟨2, accent⟩ else otherwise

def leftLabel (n : Nat) : String := if n = 1 then "1 item left" else s!"{n} items left"

def button (ui : UI) (r : ControlRef) (label : String) : Node :=
  .box { padding := ⟨6, 16, 6, 16⟩, radius := 6, border := ring ui r,
         background := some (if ui.hover = some r then accentDark else accent) }
    (some { ref := r, label })
    [.text { font := { body with weight := 600 }, color := white } label]

def inputRow (s : State) (ui : UI) : Node :=
  .box { axis := .row, width := .fill, gap := 8, align := .center } none
    [ .field { width := .fill, padding := ⟨6, 8, 6, 8⟩, background := some white, radius := 6,
               border := ring ui fieldRef (some ⟨1, line⟩) }
        { font := body, color := ink }
        { ref := fieldRef, role := .textField, label := placeholder }
        (s.field.view (ui.focus = some fieldRef)),
      button ui addRef "Add" ]

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
             background := some ⟨240, 240, 242, 255⟩ }
        (some { ref := deleteRef it.id, label := s!"Delete {it.text}" })
        [.text { font := { size := 13 }, color := ⟨200, 40, 40, 255⟩ } "Delete"] ]

def view (s : State) (ui : UI) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨20, 20, 20, 20⟩, gap := 12,
         background := some bg, clip := true } none
    [ .text { font := { size := 22, weight := 700 }, color := ink } "Fixture",
      .para { font := { size := 13 }, color := muted } {}
        "Cairn's test app. Type an item and press Enter or Add, check it off or delete it, and \
         press Flash to set a timer. Lean breaks this paragraph to the window's width.",
      inputRow s ui,
      .box { axis := .row, width := .fill, gap := 8, align := .center } none
        ([button ui flashRef "Flash"] ++
         (if s.flash then [.text { font := body, color := accent } "Flashing"] else [])),
      .box { width := .fill, gap := 4 } none (s.items.map (itemRow ui)),
      .text { font := { size := 13 }, color := muted } (leftLabel (left s)) ]

def app : App State := machine.toApp [.window 1 "Fixture" view] claimInfos

end Fixture
