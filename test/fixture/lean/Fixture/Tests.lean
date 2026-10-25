import Fixture
import Cairn.Runtime
import Cairn.Frame.Dump

/-! Runtime checks for the fixture: events in, through layout, hit testing, focus, timers and
the v1 boundary, with mono metrics (the interpreter can't call the host's Core Text). -/

namespace Fixture.Tests
open Cairn Cairn.Runtime Fixture

def tcfg : Config := {}
def run (es : List Event) : Runtime.State State := (steps app tcfg (start app tcfg ⟨480, 600⟩) es).1
def st (es : List Event) : State := (run es).app
def texts (s : State) : List (Nat × String × Bool) := s.items.map fun i => (i.id, i.text, i.done)

def at? (rs : Runtime.State State) (r : ControlRef) : Option Point :=
  (find rs.laid r).map (·.visible.center)
/-- Not one of the scroll box's rows (`^10#k`). -/
def notRow (r : ControlRef) : Bool := r.claim != 10

def clickOn (rs : Runtime.State State) (r : ControlRef) : List Event :=
  match at? rs r with
  | some p => [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}]
  | none => []

-- region: fixture-tests
def typed : List Event :=
  clickOn (run []) fieldRef ++ [.insertText "  milk ", .key .enter {}, .insertText "eggs"]
def two : List Event := typed ++ clickOn (run typed) addRef

#guard texts (st typed) == [(1, "milk", false)]
#guard texts (st two) == [(1, "milk", false), (2, "eggs", false)]
def toggled : List Event := two ++ clickOn (run two) (toggleRef 1)
#guard texts (st toggled) == [(1, "milk", true), (2, "eggs", false)]
#guard left (st toggled) == 1
def deleted : List Event := toggled ++ clickOn (run toggled) (deleteRef 2)
#guard texts (st deleted) == [(1, "milk", true)]
-- Tab order: field, Add, Passcode, Flash, then each item's checkbox and delete button (and
-- then the scroll box's rows, `notRow`).
#guard ((tabOrder (run two).laid).map (·.ref)).filter notRow ==
  [fieldRef, addRef, passRef, flashRef, toggleRef 1, deleteRef 1, toggleRef 2, deleteRef 2]
-- Flash sets its timer; the note shows until it fires.
def flashed : List Event := clickOn (run []) flashRef
#guard (st flashed).flash
-- The frame through the v1 boundary carries the keyed controls.
#guard ((decodeFrame (frameBytes Frame.boundary (run two))).map fun f =>
  (f.ax.toList.filterMap (·.control)).filter notRow) ==
  some [fieldRef, addRef, passRef, flashRef, toggleRef 1, deleteRef 1, toggleRef 2, deleteRef 2]
-- endregion: fixture-tests

-- The Passcode field: bullets on screen, nothing in the accessibility value, a redacted request.
def secret : List Event := clickOn (run []) passRef ++ [.insertText "hunter2"]
#guard (st secret).passcode.text == "hunter2"
#guard ((decodeFrame (frameBytes Frame.boundary (run secret))).map fun f =>
  (f.ax.toList.filter (·.control == some passRef)).map fun n => (n.value, n.secure)) ==
  some [("", true)]
#guard !Dump.occurs "hunter2" (Dump.canvas (Frame.ofLaid (run secret).ui (run secret).laid))
#guard (steps app tcfg (run secret) [.key .enter {}]).2.any fun
  | .request _ r => r.redact && !Dump.occurs "hunter2" (Dump.request r)
  | _ => false
#guard (st (secret ++ [.key .enter {}])).passcode.len == 0

-- region: fixture-scroll-tests
-- The scroll box: 200 rows of 32 points in a box 160 high, scrolled 1,616 points (50½ rows).
def box : Rect := ((run []).laid.children.getD 7 default).rect
def rectOf (k : Nat) : Option Rect := (find (run []).laid (rowRef k)).map (·.node.rect)
def visibleOf (k : Nat) : Option Rect := (find (run []).laid (rowRef k)).map (·.visible)
def click (p : Point) : List Event := [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}]

#guard box.h == 160
-- Every row is laid, at the column's y less the offset: row k at the box's top + 32·(k − 1) − 1616.
#guard rectOf 1 == some ⟨box.x, box.y - 1616, box.w, 32⟩
#guard rectOf 51 == some ⟨box.x, box.y - 16, box.w, 32⟩
#guard rectOf 200 == some ⟨box.x, box.y + 32 * 199 - 1616, box.w, 32⟩
-- Row 51's lower half shows, rows 52 to 55 whole, row 56's upper half; rows 50 and 57 not at all.
#guard visibleOf 51 == some ⟨box.x, box.y, box.w, 16⟩
#guard visibleOf 52 == some ⟨box.x, box.y + 16, box.w, 32⟩
#guard visibleOf 56 == some ⟨box.x, box.y + 144, box.w, 16⟩
#guard (visibleOf 50).map (·.h) == some 0
#guard (visibleOf 57).map (·.h) == some 0
-- A click at the centre of row 51's visible half selects it; just above the box, nothing.
#guard (st ((visibleOf 51).map (click ·.center) |>.getD [])).selected == some 51
#guard (st ((visibleOf 54).map (click ·.center) |>.getD [])).selected == some 54
#guard (st (click ⟨box.x + 10, box.y - 2⟩)).selected == none
-- The frame names every row (presence), draws only the six that show, and gives the box a node
-- of its own.
def frame0 : Option Frame := decodeFrame (frameBytes Frame.boundary (run []))
#guard (frame0.map fun f => ((f.ax.toList.filterMap (·.control)).filter (!notRow ·)).length) == some 200
#guard (frame0.map fun f => (f.draws.toList.filter fun
  | .text _ _ _ t => t.startsWith "Row " | _ => false).length) == some 6
#guard (frame0.map fun f => (f.ax.toList.filter (·.role == .scrollArea)).length) == some 1
-- endregion: fixture-scroll-tests

end Fixture.Tests
