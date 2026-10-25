import Examples.Todo
import Cairn.Runtime
import Cairn.Abi

/-! Runtime checks for TodoMVC: events in, through layout, hit testing, focus and the v1
boundary, with mono metrics (the interpreter can't call the host's Core Text). Each check names
the requirement it exercises (`research/todomvc`). -/

namespace Examples.Todo.Tests
open Cairn Cairn.Runtime Examples.Todo

def tcfg : Config := {}
def size : Size := ⟨560, 720⟩
def run (es : List Event) : Runtime.State State := (steps app tcfg (start app tcfg size) es).1
def st (es : List Event) : State := (run es).app
def ui (es : List Event) : UI := (run es).ui
def titles (s : State) : List (Nat × String × Bool) := s.todos.map fun t => (t.id, t.title, t.completed)
def axRefs (es : List Event) : List ControlRef :=
  ((decodeFrame (frameBytes Frame.boundary (run es))).map fun f =>
    f.ax.toList.filterMap (·.control)).getD []

/-- The centre of the control `r` on screen. -/
def at? (rs : Runtime.State State) (r : ControlRef) : Option Point :=
  (find rs.laid r).map (·.visible.center)
def clickOn (rs : Runtime.State State) (r : ControlRef) : List Event :=
  match at? rs r with
  | some p => [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}]
  | none => []
/-- A double click: the host's second pointer down carries a click count of 2 (^214). -/
def doubleClickOn (rs : Runtime.State State) (r : ControlRef) : List Event :=
  match at? rs r with
  | some p => [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {},
               .pointerDown p .primary 2 {}, .pointerUp p .primary {}]
  | none => []
def then_ (es : List Event) (f : Runtime.State State → List Event) : List Event := es ++ f (run es)

-- T5: focus starts in the new-todo field. T1: no toggle all, list or footer.
#guard (ui []).focus == some newRef
#guard axRefs [] == [newRef]

-- T6, T7, T50: Enter adds the trimmed text and clears the field; focus stays.
def one : List Event := [.insertText "  milk ", .key .enter {}]
#guard titles (st one) == [(1, "milk", false)]
#guard (st one).newField.text == [] && (ui one).focus == some newRef
-- T8: blank text adds nothing, and stays in the field.
#guard titles (st (one ++ [.insertText "   ", .key .enter {}])) == titles (st one)
#guard (st (one ++ [.insertText "   ", .key .enter {}])).newField.textString == "   "
def two : List Event := one ++ [.insertText "eggs", .key .enter {}]
#guard titles (st two) == [(1, "milk", false), (2, "eggs", false)]
-- T2, T14, T18, T39: with todos, toggle all, the rows and the footer appear.
#guard axRefs two == [toggleAllRef, newRef, toggleRef 1, titleRef 1, deleteRef 1, toggleRef 2,
  titleRef 2, deleteRef 2, filterRef .all, filterRef .active, filterRef .completed]

-- T19, T34, T37: check milk; the counter follows and Clear completed appears.
def checked : List Event := then_ two (clickOn · (toggleRef 1))
#guard titles (st checked) == [(1, "milk", true), (2, "eggs", false)]
#guard (st checked).left == 1 && (run checked).laid.controls.any (·.ref == clearRef)

-- T20, T25: a double click on a title enters edit mode with focus in the edit field.
def editing : List Event := then_ two (doubleClickOn · (titleRef 1))
#guard (st editing).editing.map (·.id) == some 1
#guard (ui editing).focus == some (editRef 1)
#guard (st editing).editing.map (·.field.textString) == some "milk"
#guard (axRefs editing).contains (editRef 1) && !(axRefs editing).contains (toggleRef 1)
-- T28, T50: Enter saves the trimmed text and returns focus to the new-todo field.
def saved : List Event := editing ++ [.selectAll, .insertText " oat milk ", .key .enter {}]
#guard titles (st saved) == [(1, "oat milk", false), (2, "eggs", false)]
#guard (st saved).editing == none && (ui saved).focus == some newRef
-- T31: Escape discards the edit, even with the field emptied, and nothing commits after.
def escaped : List Event := editing ++ [.selectAll, .key .backspace {}, .key .escape {}]
#guard titles (st escaped) == titles (st two)
#guard (st escaped).editing == none && (ui escaped).focus == some newRef
#guard titles (st (then_ escaped (clickOn · (filterRef .all)))) == titles (st two)
-- T29, T30, T33: a click elsewhere saves first (blank deletes), then does its own thing.
def blurred : List Event :=
  then_ (editing ++ [.selectAll, .key .backspace {}]) (clickOn · toggleAllRef)
#guard titles (st blurred) == [(2, "eggs", true)]
#guard (st blurred).editing == none
-- …unless saving moved what was clicked: deleting todo 1 moves todo 2's row up, so the release
-- is no longer over the checkbox that was pressed, and the click does nothing (as in a browser).
#guard titles (st (then_ (editing ++ [.selectAll, .key .backspace {}]) (clickOn · (toggleRef 2)))) ==
  [(2, "eggs", false)]
-- T29: Tab away saves too.
#guard titles (st (editing ++ [.insertText " too", .key .tab {}])) ==
  [(1, "milk too", false), (2, "eggs", false)]

-- T16: toggle all completes every todo, then makes them all active again.
def allOn : List Event := then_ two (clickOn · toggleAllRef)
#guard (st allOn).todos.all (·.completed) && (st allOn).left == 0
#guard (st (then_ allOn (clickOn · toggleAllRef))).todos.all (!·.completed)

-- T40, T42, T43: Active lists only active todos; the counter and pending text don't change.
def activeOnly : List Event :=
  then_ (then_ checked (clickOn · newRef) ++ [.insertText "draft"]) (clickOn · (filterRef .active))
#guard (visible (st activeOnly)).map (·.id) == [2]
#guard (st activeOnly).left == 1 && (st activeOnly).newField.textString == "draft"
#guard ((axRefs activeOnly).filter fun r => r.claim == 204) == [toggleRef 2]
-- T38: Clear completed removes completed todos only.
#guard titles (st (then_ checked (clickOn · clearRef))) == [(2, "eggs", false)]
-- T22: delete removes that todo and nothing else.
#guard titles (st (then_ two (clickOn · (deleteRef 1)))) == [(2, "eggs", false)]

-- T21, T49: the delete button is always in the tree, its glyph drawn only on hover or focus.
def delGlyph (rs : Runtime.State State) (k : Nat) : Bool := hot rs.ui k
#guard !delGlyph (run two) 1
#guard delGlyph (run (then_ two fun rs => (at? rs (titleRef 1)).toList.map .pointerMove)) 1
-- Tab order (T49: delete is reachable by keyboard); the title is not a stop.
#guard (tabOrder (run two).laid).map (·.ref) ==
  [toggleAllRef, newRef, toggleRef 1, deleteRef 1, toggleRef 2, deleteRef 2,
   filterRef .all, filterRef .active, filterRef .completed]

-- T35: the plural.
#guard itemsWord 0 == " items left" && itemsWord 1 == " item left" && itemsWord 2 == " items left"

end Examples.Todo.Tests
