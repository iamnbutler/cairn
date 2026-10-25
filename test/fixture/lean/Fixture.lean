module

public import Cairn

/-! # Fixture: Cairn's own test app

What the framework's checks need from an app, in one small window (test/fixture/README.md): a
heading and a wrapped paragraph (text, `Node.para`), a text field with Enter (editing, the text
input client), a secure field (a passcode, sent in a redacted request), a button, a list of rows with keyed controls (hit testing, `^N#k`), a button whose
effect comes back as a message (a timer), an invariant with a runnable check, a flow, and a virtual list (`VList`) of 10,000 keyed rows of mixed
height whose offset the runtime owns, ending in a line that hears `appear`, with buttons that add rows at its top and its end.

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
| ^9 | move | the Passcode field: a secure field; Enter sends it in a redacted request |
| ^10 | move, keyed | a row of the list, `^10#k` for row `k`: selects it (a selected row is taller) |
| ^11 | retired | the rows at a fixed offset (replaced by ^15) |
| ^12 | invariant | the rows don't overlap, and what shows of them is inside the box |
| ^13 | invariant | a row is pressed at the centre of what shows of it, and nowhere if nothing does |
| ^14 | place | the virtual list of rows; its ref keys the offset and the heights the runtime owns |
| ^15 | retired | the rows at the column's place less the offset (replaced by ^19) |
| ^16 | move | the end of the rows comes into view (`appear`): counts it |
| ^17 | move | Add above: a row at the top of the list |
| ^18 | move | Add below: a row at the end of the list, above the end line |
| ^19 | invariant | the rows laid are one under the other from the box's top less the offset |
| ^20 | invariant | the rows laid are exactly those that meet the box widened by the overscan, and no more than its height allows |

^12, ^13, ^19 and ^20 are Cairn's scroll-box and virtual-list theorems (`Cairn.Layout.Scroll`,
`Cairn.UI.VList`, `Cairn.Layout.VList`) stated for this list; they and their proofs are in
`Checks/Scroll.lean`, which can import the layout proofs.

Its claims are `fixture^N`, in test/fixture/claims.lock. None of them is in Cairn's ledger, so
changing the fixture never moves a Cairn claim. -/

@[expose] public section

namespace Fixture
open Cairn Cairn.Claims

def placeholder : String := "New item"
def passPlaceholder : String := "Passcode"

-- region: fixture-state
/-- The list's rows at first, numbered from 1 (keyed controls never use key 0), then key 0 for
the end line. -/
def rowCount : Nat := 10000
def initKeys : Array Nat := (Array.range rowCount).map (· + 1) |>.push 0

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
  /-- The Passcode field: a secure field (docs/text.md, "Secure fields"). -/
  passcode : Text.SecureField := Text.SecureField.empty passPlaceholder
  /-- The id the next request gets. -/
  nextReq : Nat := 0
  /-- The scroll box's row last pressed. -/
  selected : Option Nat := none
  /-- How many times the end of the rows has come into view (^16). -/
  ends : Nat := 0
  /-- The list's rows, top to bottom, by key: `1` to `rowCount` at first, then the end line's
  key, `0`. The view reads the array as it is (`VList.node`), so it is kept here, not rebuilt. -/
  keys : Array Nat := initKeys
  /-- The key the next added row gets. -/
  nextKey : Nat := rowCount + 1
deriving Repr, DecidableEq, Inhabited

def fieldRef : ControlRef := ⟨2, 0⟩
def addRef : ControlRef := ⟨3, 0⟩
def toggleRef (k : Nat) : ControlRef := ⟨4, k⟩
def deleteRef (k : Nat) : ControlRef := ⟨5, k⟩
def flashRef : ControlRef := ⟨6, 0⟩
def passRef : ControlRef := ⟨9, 0⟩
def rowRef (k : Nat) : ControlRef := ⟨10, k⟩
/-- The scroll box's ref, keyed by its place: the runtime keeps its offset under it. -/
def rowsRef : ControlRef := ⟨14, 0⟩
def endRef : ControlRef := ⟨16, 0⟩
def addTopRef : ControlRef := ⟨17, 0⟩
def addEndRef : ControlRef := ⟨18, 0⟩
-- endregion: fixture-state

-- region: fixture-flash-timer
/-- The timer Flash sets, and how long the note shows. -/
def flashTimer : String := "flash"
def flashMs : Nat := 400
-- endregion: fixture-flash-timer

/-- Where Enter in the Passcode field sends it. Nothing listens there; the request is what
the fuzzer and the frame dump check (`Request.redact`). -/
def signInUrl : String := "http://127.0.0.1:9/sign-in"

/-- The passcode in a request's body, marked `redact`, so dumps, the debug socket and fuzz
reports print its size only. -/
def signIn (p : Text.SecureField) : Request :=
  .http "POST" signInUrl [] p.text.toUTF8 5000 (redact := true)

/-! ## The model -/

-- region: fixture-add
/-- The field's text without leading and trailing whitespace. -/
def trimmed (t : List Char) : List Char :=
  ((t.dropWhile Char.isWhitespace).reverse.dropWhile Char.isWhitespace).reverse

/-- Add the field's trimmed text as a new item and clear the field; nothing when it's blank. -/
def add (s : State) : State :=
  if trimmed s.field.text = [] then s
  else
    { s with items := s.items ++ [{ id := s.nextId, text := String.ofList (trimmed s.field.text) }],
             nextId := s.nextId + 1, field := Text.Field.empty placeholder }
-- endregion: fixture-add

def has (s : State) (k : Nat) : Bool := s.items.any (·.id == k)

def flip (k : Nat) (i : Item) : Item := if i.id = k then { i with done := !i.done } else i

def toggle (k : Nat) (s : State) : State := { s with items := s.items.map (flip k) }

def delete (k : Nat) (s : State) : State := { s with items := s.items.filter (·.id ≠ k) }

def left (s : State) : Nat := (s.items.filter (!·.done)).length

-- region: fixture-add-inv
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
-- endregion: fixture-add-inv

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

-- region: fixture-place
place ^1 window "Fixture window" where
  does "The window: a heading, a paragraph, the New item field and Add, the Passcode field, Flash, the items and the count left."
-- endregion: fixture-place

-- region: fixture-type-item
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
-- endregion: fixture-type-item

-- region: fixture-add-item
move ^3 addItem (s : State) "Add" in ^1 where
  does "Press Add."
  sees "The field's text, trimmed, is added at the end of the list and the field is cleared. Blank text changes nothing."
  on press
    apply := add s
    post s' := s' = add s
    sound := by intro s; rfl
-- endregion: fixture-add-item

-- region: fixture-toggle
move ^4 toggleItem (s : State) (k : Nat) "Toggle an item" in ^1 where
  does "Press an item's checkbox."
  sees "The item is marked done, or not done again."
  enabled := has s k
  on press
    apply := toggle k s
    post s' := s'.items = s.items.map (flip k)
    sound := by intro s k _; rfl
-- endregion: fixture-toggle

-- region: fixture-delete
move ^5 deleteItem (s : State) (k : Nat) "Delete an item" in ^1 where
  does "Press an item's delete button."
  sees "The item is gone, and its checkbox and delete button with it."
  enabled := has s k
  on press
    apply := delete k s
    post s' := s'.items = s.items.filter (·.id ≠ k)
    sound := by intro s k _; rfl
-- endregion: fixture-delete

-- region: fixture-flash
move ^6 flashMove (s : State) "Flash" in ^1 where
  does "Press Flash."
  sees "A note shows, and goes when the timer the press set fires."
  on press
    emit := ({ s with flash := true }, [.setTimer flashTimer flashMs])
    post s' := s'.flash = true ∧ s'.items = s.items
    sound := by intro s; exact ⟨rfl, rfl⟩
-- endregion: fixture-flash

move ^9 typePasscode (s : State) "Type a passcode" in ^1 where
  does "Type in the Passcode field, and press Enter."
  sees "One bullet per character; copy, cut and undo beep. Enter sends the passcode in a redacted request and clears the field."
  on edit (op : TextOp)
    emit := ({ s with passcode := (Text.SecureField.apply op s.passcode).1 },
      (Text.SecureField.apply op s.passcode).2)
    post s' := s'.passcode = (Text.SecureField.apply op s.passcode).1 ∧ s'.items = s.items ∧
      s'.nextId = s.nextId
    sound := by intro s op; exact ⟨rfl, rfl, rfl⟩
  on submit
    emit := ({ s with passcode := Text.SecureField.empty passPlaceholder, nextReq := s.nextReq + 1 },
      [.request s.nextReq (signIn s.passcode)])
    post s' := s'.passcode = Text.SecureField.empty passPlaceholder ∧ s'.items = s.items ∧
      s'.nextId = s.nextId
    sound := by intro s; exact ⟨rfl, rfl, rfl⟩

-- region: fixture-scroll-rows
/-- The list: each row's height (mixed, 24 to 48 points, and 72 when selected), the end line's,
and the box's height. The runtime owns its offset (`ui.scrollOf rowsRef`) and the heights it has
laid (`ui.listOf rowsRef`); it opens at the top. -/
def rowH (s : State) (k : Nat) : Nat := if s.selected = some k then 72 else 24 + 8 * (k % 4)
def endH : Nat := 32
def rowsH : Nat := 160

place ^14 rowsPlace "The rows" in ^1 where
  does "The virtual list of 10,000 rows of mixed height and the end line under them. Cairn owns its offset and lays only the rows near the view: the wheel, the trackpad and the page keys move it, and the app never hears a scroll."

/-- Rows are numbered from 1, and every key below `nextKey` is a row (none is ever removed). -/
def isRow (s : State) (k : Nat) : Bool := 1 ≤ k && k < s.nextKey

move ^10 selectRow (s : State) (k : Nat) "Select a row" in ^1 where
  does "Press a row of the list."
  sees "The row is highlighted and grows to 72 points; the one selected before shrinks back."
  enabled := isRow s k
  on press
    apply := { s with selected := some k }
    post s' := s'.selected = some k ∧ s'.items = s.items
    sound := by intro s k _; exact ⟨rfl, rfl⟩

move ^16 reachEnd (s : State) "Reach the end of the rows" in ^14 where
  does "Scroll the rows to their end."
  sees "The end line comes into view and counts one more visit."
  on appear
    apply := { s with ends := s.ends + 1 }
    post s' := s'.ends = s.ends + 1 ∧ s'.items = s.items ∧ s'.selected = s.selected
    sound := by intro s; exact ⟨rfl, rfl, rfl⟩

move ^17 addTop (s : State) "Add a row above" in ^1 where
  does "Press Add above."
  sees "A row is added at the top of the list; the rows showing stay where they are."
  on press
    apply := { s with keys := #[s.nextKey] ++ s.keys, nextKey := s.nextKey + 1 }
    post s' := s'.keys = #[s.nextKey] ++ s.keys ∧ s'.items = s.items
    sound := by intro s; exact ⟨rfl, rfl⟩

move ^18 addEnd (s : State) "Add a row below" in ^1 where
  does "Press Add below."
  sees "A row is added at the end of the list, above the end line."
  on press
    apply := { s with keys := s.keys.pop.push s.nextKey |>.push 0, nextKey := s.nextKey + 1 }
    post s' := s'.items = s.items ∧ s'.nextKey = s.nextKey + 1
    sound := by intro s; exact ⟨rfl, rfl⟩
-- endregion: fixture-scroll-rows

-- region: fixture-receive
/-- The world's messages: Flash's timer clears the note. -/
def receive (s : State) : Msg → State × List Effect
  | .timer n => (if n = flashTimer then { s with flash := false } else s, [])
  | _ => (s, [])
-- endregion: fixture-receive

-- region: fixture-machine
def machine : Machine State := { init := {}, moves := moves%, receive }
-- endregion: fixture-machine

-- region: fixture-invariant
invariant ^7 idsBelow "Item ids stay below the next id" for machine where
  does "Every item's id is positive and below the id the next item gets, in every reachable state."
  holds s := Inv s
  init := ⟨Nat.one_pos, fun _ h => by simp only [machine, List.not_mem_nil] at h⟩
  step := machine.preserves <|
    Move.all_cons (typeItem.preserves _ (fun _ _ h => h) fun _ h => add_inv h)
      (Move.all_cons (addItem.preserves _ fun _ h => add_inv h)
      (Move.all_cons (toggleItem.preserves _ fun _ k _ h => toggle_inv k h)
      (Move.all_cons (deleteItem.preserves _ fun _ k _ h => delete_inv k h)
      (Move.all_cons (flashMove.preserves _ fun _ h => h)
      (Move.all_cons (typePasscode.preserves _ (fun _ _ h => h) fun _ h => h)
      (Move.all_cons (selectRow.preserves _ fun _ _ _ h => h)
      (Move.all_cons (reachEnd.preserves _ fun _ h => h)
      (Move.all_cons (addTop.preserves _ fun _ h => h)
      (Move.all_cons (addEnd.preserves _ fun _ h => h) Move.all_nil)))))))))
  receive := by
    intro s m h
    cases m with
    | timer n =>
      show Inv (if n = flashTimer then { s with flash := false } else s)
      split <;> exact h
    | _ => exact h
-- endregion: fixture-invariant

-- region: fixture-flow
flow ^8 addAndFinish "Add two items and finish one" for machine where
  does "Type milk and press Enter, type eggs and press Add, then check milk."
  sees "Two items, milk done."
  goal s := s.items.map (·.text) = ["milk", "eggs"] ∧ s.items.map (·.done) = [true, false]
  witness edit ^2 (.insert "milk"), submit ^2, edit ^2 (.insert " eggs "), press ^3, press ^4#1
-- endregion: fixture-flow

-- region: fixture-claims
def claimInfos : List ClaimInfo := claims%
-- endregion: fixture-claims

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

-- region: fixture-button
def button (ui : UI) (r : ControlRef) (label : String) : Node :=
  .box { padding := ⟨6, 16, 6, 16⟩, radius := 6, border := ring ui r,
         background := some (if ui.hover = some r then accentDark else accent) }
    (some { ref := r, label })
    [.text { font := { body with weight := 600 }, color := white } label]
-- endregion: fixture-button

-- region: fixture-input-row
def inputRow (s : State) (ui : UI) : Node :=
  .box { axis := .row, width := .fill, gap := 8, align := .center } none
    [ .field { width := .fill, padding := ⟨6, 8, 6, 8⟩, background := some white, radius := 6,
               border := ring ui fieldRef (some ⟨1, line⟩) }
        { font := body, color := ink }
        { ref := fieldRef, role := .textField, label := placeholder }
        (s.field.view (ui.focus = some fieldRef)),
      button ui addRef "Add" ]
-- endregion: fixture-input-row

def passcodeRow (s : State) (ui : UI) : Node :=
  .field { width := .fill, padding := ⟨6, 8, 6, 8⟩, background := some white, radius := 6,
           border := ring ui passRef (some ⟨1, line⟩) }
    { font := body, color := ink }
    { ref := passRef, role := .textField, label := passPlaceholder }
    (s.passcode.view (ui.focus = some passRef))

-- region: fixture-item-row
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
-- endregion: fixture-item-row

-- region: fixture-scroll-view
/-- Row `k`: a clipped button labelled with its number, `rowH s k` high. -/
def row (s : State) (ui : UI) (k : Nat) : Node :=
  .box { width := .fill, height := .fixed (rowH s k), clip := true, align := .center,
         padding := ⟨0, 12, 0, 12⟩, border := ring ui (rowRef k),
         background := some (if s.selected = some k then accent
           else if ui.hover = some (rowRef k) then ⟨226, 232, 255, 255⟩
           else if k % 2 = 0 then ⟨240, 241, 245, 255⟩ else white) }
    (some { ref := rowRef k, label := s!"Row {k}", selected := s.selected = some k })
    [.text { font := { size := 13 }, color := if s.selected = some k then white else ink }
      s!"Row {k}"]

/-- The line after the last row, marked `appear`: the runtime tells the app (^16) each time it
comes into view. -/
def endLine (s : State) : Node :=
  .box { width := .fill, height := .fixed endH, align := .center, padding := ⟨0, 12, 0, 12⟩ }
    (some { ref := endRef, role := .text, label := "End of the rows", appear := true })
    [.text { font := { size := 13 }, color := muted }
      s!"End of the rows · reached {s.ends} {if s.ends = 1 then "time" else "times"}"]

/-- The row with key `k`: the end line for `0`. -/
def rowOf (s : State) (ui : UI) (k : Nat) : Node := if k = 0 then endLine s else row s ui k

/-- The list: its ref keys the offset and the heights the runtime keeps; it estimates the rows
it hasn't laid at the mean of those it has. -/
def rowsList : VList := { ref := rowsRef, style := { width := .fill, height := .fixed rowsH } }

/-- The virtual list of rows: only those near the runtime's offset are built. -/
def rowsBox (s : State) (ui : UI) : Node := VList.node rowsList ui s.keys (rowOf s ui)
-- endregion: fixture-scroll-view

-- region: fixture-view
def view (s : State) (ui : UI) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨20, 20, 20, 20⟩, gap := 12,
         background := some bg, clip := true } none
    [ .text { font := { size := 22, weight := 700 }, color := ink } "Fixture",
      -- region: fixture-para
      .para { font := { size := 13 }, color := muted } {}
        "Cairn's test app. Type an item and press Enter or Add, check it off or delete it, and \
         press Flash to set a timer. Lean breaks this paragraph to the window's width.",
      -- endregion: fixture-para
      inputRow s ui,
      passcodeRow s ui,
      .box { axis := .row, width := .fill, gap := 8, align := .center } none
        ([button ui flashRef "Flash", button ui addTopRef "Add above",
          button ui addEndRef "Add below"] ++
         (if s.flash then [.text { font := body, color := accent } "Flashing"] else [])),
      .box { width := .fill, gap := 4 } none (s.items.map (itemRow ui)),
      .text { font := { size := 13 }, color := muted } (leftLabel (left s)),
      rowsBox s ui ]
-- endregion: fixture-view

-- region: fixture-app
def app : App State := machine.toApp [.window 1 "Fixture" view] claimInfos
-- endregion: fixture-app

end Fixture
