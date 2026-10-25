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
/-- Not in the scroll box: one of its rows (`^10#k`) or its end line (^16). -/
def notRow (r : ControlRef) : Bool := r.claim != 10 && r.claim != 16

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
-- The scroll box: 200 rows of 32 points and the end line in a box 160 high. It opens at the top;
-- a wheel tick over it of 1,616 points (50½ rows) scrolls it there.
def box : Rect := ((run []).laid.children.getD 7 default).rect
def down : List Event := [.scroll box.center 0 1616]
def rectOf (k : Nat) : Option Rect := (find (run down).laid (rowRef k)).map (·.node.rect)
def visibleOf (k : Nat) : Option Rect := (find (run down).laid (rowRef k)).map (·.visible)
def click (p : Point) : List Event := [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}]
def offset (es : List Event) : Int := (run es).ui.scrollOf rowsRef

#guard box.h == 160
#guard offset [] == 0
#guard (find (run []).laid (rowRef 1)).map (·.node.rect) == some ⟨box.x, box.y, box.w, 32⟩
#guard offset down == 1616
-- The app hears nothing of it: its state is the same.
#guard st down == st []
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
#guard (st (down ++ ((visibleOf 51).map (click ·.center) |>.getD []))).selected == some 51
#guard (st (down ++ ((visibleOf 54).map (click ·.center) |>.getD []))).selected == some 54
#guard (st (down ++ click ⟨box.x + 10, box.y - 2⟩)).selected == none
-- The offset is clamped: content 201 × 32 = 6,432, so at most 6,432 − 160 = 6,272; and back to 0.
#guard offset [.scroll box.center 0 100000] == 6272
#guard offset [.scroll box.center 0 100, .scroll box.center 0 (-5000)] == 0
-- Keys move the box under the pointer: a page is the box less a line (120), End goes to the end.
#guard offset [.pointerMove box.center, .key .pageDown {}] == 120
#guard offset [.pointerMove box.center, .key .finish {}] == 6272
#guard offset [.pointerMove box.center, .key .finish {}, .key .home {}] == 0
-- The end line comes into view at the end: ^16 counts it, once per visit.
#guard (st [.scroll box.center 0 100000]).ends == 1
#guard (st [.scroll box.center 0 100000, .scroll box.center 0 (-10)]).ends == 1
#guard (st [.scroll box.center 0 100]).ends == 0
#guard (((steps app tcfg (run [.scroll box.center 0 100000]) [.scroll box.center 0 (-100000)]).1 |>
  fun r => steps app tcfg r [.scroll box.center 0 100000]).1.app.ends) == 2
-- Tab from the last control before the rows goes to row 1, then on down; shift-Tab from nothing
-- goes to row 200 and scrolls it into view (just above the end line).
#guard (run [.key .tab { shift := true }]).ui.focus == some (rowRef 200)
#guard offset [.key .tab { shift := true }] == 32 * 199 + 32 - 160
-- The frame names every row (presence), draws only the six that show, and gives the box a node
-- of its own.
def frame0 : Option Frame := decodeFrame (frameBytes Frame.boundary (run down))
#guard (frame0.map fun f => ((f.ax.toList.filterMap (·.control)).filter (·.claim == 10)).length) == some 200
#guard (frame0.map fun f => (f.draws.toList.filter fun
  | .text _ _ _ t => t.startsWith "Row " | _ => false).length) == some 6
#guard (frame0.map fun f => (f.ax.toList.filter (·.role == .scrollArea)).length) == some 1
-- endregion: fixture-scroll-tests

end Fixture.Tests
