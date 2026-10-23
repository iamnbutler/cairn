import Cairn.Runtime.Abi
import Cairn.Runtime.Stub

/-! Concrete checks of the runtime on a small app, laid out by the stub layout. -/

namespace Cairn.Runtime.Tests

open Cairn

/-- Records every action it is given, so tests can read what the runtime delivered. -/
structure TState where
  count : Nat := 0
  text : String := ""
  caret : Nat := 0
  log : List Action := []
deriving Inhabited

def ref (n : Nat) : ControlRef := { claim := n }

def btn (n : Nat) (label : String) : Node :=
  .box { width := .fixed 100, height := .fixed 30, background := some ⟨200, 200, 200, 255⟩ }
    (some { ref := ref n, label }) [.text {} label]

/-- ^1 increment, ^2 a field, ^3 a button with a static label (no control role), ^4 reset when
the count is positive, and ^5 a delete button shown only while ^1 is hovered. -/
def view (s : TState) (ui : UI) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨10, 10, 10, 10⟩, gap := 10 } none <|
    [btn 1 "Increment",
     .field { width := .fixed 200 } {} { ref := ref 2, role := .textField, label := "Name" }
       { text := s.text, caret := s.caret, anchor := s.caret, focused := ui.focus == some (ref 2) },
     btn 3 "Label"] ++
    (if s.count > 0 then [btn 4 "Reset"] else []) ++
    (if ui.hover == some (ref 1) then [btn 5 "Delete"] else [])

def update (s : TState) (a : Action) : TState × List Effect :=
  let s := { s with log := s.log ++ [a] }
  match a with
  | .press c => if c == ref 1 then ({ s with count := s.count + 1 }, [])
      else if c == ref 4 then ({ s with count := 0 }, []) else (s, [])
  | .edit _ (.insert t) => ({ s with text := s.text ++ t, caret := s.caret + t.length }, [])
  | .edit _ (.setCaret i _) => ({ s with caret := i }, [])
  | .edit _ .copy => (s, [.setClipboard s.text])
  | _ => (s, [])

def app : App TState := { init := {}, view, update, claims := [] }
def cfg : Config := { layout := Stub.layout }
def s0 : State TState := start app cfg ⟨800, 600⟩

def run (es : List Event) : State TState × List Effect := steps app cfg s0 es
def log (es : List Event) : List Action := (run es).1.app.log
def ui (es : List Event) : UI := (run es).1.ui

def down (x y : Int) (clicks : Nat := 1) (mods : Mods := {}) : Event := .pointerDown ⟨x, y⟩ .primary clicks mods
def up (x y : Int) : Event := .pointerUp ⟨x, y⟩ .primary {}
def click (x y : Int) : List Event := [down x y, up x y]

-- Layout: ^1 at (10,10,100,30), ^2 at (10,50,200,21), ^3 at (10,81,100,30).
#guard (targets s0.laid).map (·.ref.claim) == [1, 2, 3]
#guard hitRef s0.laid ⟨60, 25⟩ == some (ref 1)
#guard hitRef s0.laid ⟨60, 45⟩ == none     -- in the gap
#guard hitRef s0.laid ⟨5, 5⟩ == none       -- root has no control and doesn't paint

-- A click presses; the count goes up and reset appears.
#guard log (click 60 25) == [.press (ref 1)]
#guard (run (click 60 25)).1.app.count == 1
-- The pointer is still over ^1, so ^5 shows too.
#guard (targets (run (click 60 25)).1.laid).map (·.ref.claim) == [1, 2, 3, 4, 5]
-- Pressed while down, cleared after.
#guard (ui [down 60 25]).pressed == some (ref 1)
#guard (ui (click 60 25)).pressed == none
-- Slide off: press on ^1, release on ^3: nothing.
#guard log [down 60 25, up 60 95] == []
-- Release in empty space: nothing.
#guard log [down 60 25, up 500 500] == []
-- Press elsewhere, release on ^1: nothing.
#guard log [down 500 500, up 60 25] == []
-- Double click: press, then double press.
#guard log [down 60 95, up 60 95, down 60 95 2, up 60 95] == [.press (ref 3), .doublePress (ref 3)]

-- Hover follows pointerMove alone, and the view can reveal on hover (^5).
#guard (ui [.pointerMove ⟨60, 25⟩]).hover == some (ref 1)
#guard (targets (run [.pointerMove ⟨60, 25⟩]).1.laid).map (·.ref.claim) == [1, 2, 3, 5]
#guard (ui [.pointerMove ⟨60, 25⟩, .pointerMove ⟨500, 500⟩]).hover == none
#guard (ui [.pointerMove ⟨60, 25⟩, .pointerExit]).hover == none
#guard cursor (run [.pointerMove ⟨60, 25⟩]).1 == .pointer
#guard cursor (run [.pointerMove ⟨60, 60⟩]).1 == .text
#guard cursor (run [.pointerMove ⟨500, 500⟩]).1 == .arrow
-- Hover is recomputed after the tree changes under a still pointer: after the first click,
-- ^4 (Reset) sits at y 112..142; clicking it removes it, and the pointer is then over nothing.
#guard (ui (click 60 25 ++ click 60 125)).hover == none
#guard (run (click 60 25 ++ click 60 125)).1.app.count == 0

-- Clicking the field focuses it and puts the caret at the nearest boundary. Mono metrics:
-- 13pt → 7 px per scalar; text origin x = 14.
#guard (ui (click 100 60)).focus == some (ref 2)
#guard log (click 100 60) == [.edit (ref 2) (.setCaret 0 false)]
#guard log ([down 100 60, up 100 60, .insertText "hello"] ++ click 30 60) ==
  [.edit (ref 2) (.setCaret 0 false), .edit (ref 2) (.insert "hello"), .edit (ref 2) (.setCaret 2 false)]
-- Shift-click extends; dragging extends.
#guard log ([.insertText "x"] ++ click 100 60 ++ [.insertText "hello", down 30 60 1 { shift := true }]) ==
  [.edit (ref 2) (.setCaret 0 false), .edit (ref 2) (.insert "hello"), .edit (ref 2) (.setCaret 2 true)]
#guard log ([down 100 60, .insertText "hello", .pointerMove ⟨35, 60⟩]) ==
  [.edit (ref 2) (.setCaret 0 false), .edit (ref 2) (.insert "hello"), .edit (ref 2) (.setCaret 3 true)]
-- Clicking outside the focused field blurs it.
#guard log (click 100 60 ++ click 500 500) == [.edit (ref 2) (.setCaret 0 false), .blur (ref 2)]
#guard (ui (click 100 60 ++ click 500 500)).focus == none
#guard log (click 100 60 ++ click 60 25) == [.edit (ref 2) (.setCaret 0 false), .blur (ref 2), .press (ref 1)]

-- Typing goes to the focused field only.
#guard log [.insertText "a"] == []
#guard (run (click 100 60 ++ [.insertText "a", .insertText "b"])).1.app.text == "ab"
#guard log (click 100 60 ++ [.key .enter {}, .key .escape {}, .key .backspace { option := true },
    .key .left { shift := true, command := true }, .copy]) ==
  [.edit (ref 2) (.setCaret 0 false), .submit (ref 2), .cancel (ref 2),
   .edit (ref 2) .deleteWordBackward, .edit (ref 2) (.moveHome true), .edit (ref 2) .copy]
#guard (run (click 100 60 ++ [.insertText "hi", .copy])).2 == [.setClipboard "hi"]
-- A replacement range selects first, clamped to the text.
#guard log (click 100 60 ++ [.insertText "hi", .insertText "yo" (some (1, 9))]) ==
  [.edit (ref 2) (.setCaret 0 false), .edit (ref 2) (.insert "hi"),
   .edit (ref 2) (.setCaret 1 false), .edit (ref 2) (.setCaret 2 true), .edit (ref 2) (.insert "yo")]

-- Tab order is paint order and wraps; shift-tab goes back. Tabbing into a field selects all,
-- tabbing out of it blurs it.
def tab (back : Bool := false) : Event := .key .tab { shift := back }
#guard (ui [tab]).focus == some (ref 1)
#guard (ui [tab, tab]).focus == some (ref 2)
#guard (ui [tab, tab, tab, tab]).focus == some (ref 1)
#guard (ui [tab true]).focus == some (ref 3)
#guard (ui [tab, tab true]).focus == some (ref 3)
#guard log [tab, tab, tab] == [.edit (ref 2) .selectAll, .blur (ref 2)]
-- Enter and space press a focused button.
#guard log [tab, .key .enter {}, .insertText " "] == [.press (ref 1), .press (ref 1)]

-- Focus on a control that vanishes is dropped: focus ^4 (Reset) and press it.
def resetByKey : List Event := click 60 25 ++ [.pointerMove ⟨500, 500⟩, tab true]
#guard (ui resetByKey).focus == some (ref 4)
#guard (ui (resetByKey ++ [.key .enter {}])).focus == none
#guard (run (resetByKey ++ [.key .enter {}])).1.app.count == 0

-- Window events.
#guard (ui [.resize ⟨1024, 768⟩]).size == ⟨1024, 768⟩
#guard (ui [down 60 25, .windowFocus false]).pressed == none
#guard log [down 60 25, .windowFocus false, up 60 25] == []

-- The byte ABI with the stub codec: two spike-format clicks on ^1.
def evBytes : ByteArray := Id.run do
  let mut b := ByteArray.empty
  for k in [1, 2, 1, 2] do
    b := Spike.pushI32 (Spike.pushI32 (b.push k) 60) 25
  return b
def boundary : Boundary := { decode := Stub.decode, render := Stub.frame, encode := Stub.encode }
#guard (stepBytes app cfg boundary (initState app cfg 800 600 200) evBytes).app.count == 2
#guard (frameBytes boundary (initState app cfg 800 600 200)).size > 16

end Cairn.Runtime.Tests
