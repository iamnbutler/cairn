import Examples.Basics
import Cairn.Runtime

/-! Runtime checks for Basics: events in, through layout, hit testing, focus and the v1
boundary, with mono metrics (the interpreter can't call the host's Core Text). -/

namespace Examples.Basics.Tests
open Cairn Cairn.Runtime Examples.Basics

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
-- region: basics-tests-delete
-- Toggle item 1, then delete item 2.
def toggled : List Event := two ++ clickOn (run two) (toggleRef 1)
#guard texts (st toggled) == [(1, "milk", true), (2, "eggs", false)]
#guard footer (st toggled) == "1 item left"
def deleted : List Event := toggled ++ clickOn (run toggled) (deleteRef 2)
#guard texts (st deleted) == [(1, "milk", true)]
#guard footer (st deleted) == "0 items left"
-- endregion: basics-tests-delete
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

end Examples.Basics.Tests
