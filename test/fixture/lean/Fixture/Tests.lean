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
/-- Not in the list: one of its rows (`^10#k`) or its end line (^16). -/
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
-- Tab order: field, Add, Passcode, Flash, Add above, Add below, then each item's checkbox and
-- delete button, the posts' Like buttons (and then the list's rows, `notRow`).
#guard ((tabOrder (run two).laid).map (·.ref)).filter notRow ==
  [fieldRef, addRef, passRef, flashRef, addTopRef, addEndRef, toggleRef 1, deleteRef 1,
   toggleRef 2, deleteRef 2, likeRef 1, likeRef 2, likeRef 3, likeRef 4]
-- Flash sets its timer; the note shows until it fires.
def flashed : List Event := clickOn (run []) flashRef
#guard (st flashed).flash
-- The frame through the v1 boundary carries the keyed controls.
#guard ((decodeFrame (frameBytes Frame.boundary (run two))).map fun f =>
  (f.ax.toList.filterMap (·.control)).filter notRow) ==
  some [fieldRef, addRef, passRef, flashRef, addTopRef, addEndRef, toggleRef 1, deleteRef 1,
        toggleRef 2, deleteRef 2, likeRef 1, likeRef 2, likeRef 3, likeRef 4]
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
-- The list: 10,000 rows of 24 to 48 points (row k is 24 + 8·(k mod 4)) and the end line, in a box
-- 160 high. It opens at the top, and lays only the rows that meet the box widened by 200 points
-- above and below: rows 1 to 10 (360 points).
def box : Rect := ((run []).laid.children.getD 8 default).rect
def rectIn (rs : Runtime.State State) (k : Nat) : Option Rect := (find rs.laid (rowRef k)).map (·.node.rect)
def rectOf (es : List Event) (k : Nat) : Option Rect := rectIn (run es) k
def click (p : Point) : List Event := [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}]
def offset (es : List Event) : Int := (run es).ui.scrollOf rowsRef
/-- The rows the list laid: their keys. -/
def laidKeys (es : List Event) : List Nat :=
  ((targets (run es).laid).map (·.ref)).filterMap fun r => if r.claim = 10 then some r.key else none
/-- Each laid row starts where the one before it ends. -/
def stacked (es : List Event) : Bool :=
  let rs := (laidKeys es).filterMap (rectOf es)
  (rs.zip (rs.drop 1)).all fun (a, b) => b.y == a.y + a.h

#guard box.h == 160
#guard offset [] == 0
#guard laidKeys [] == List.range' 1 10
#guard rectOf [] 1 == some ⟨box.x, box.y, box.w, 32⟩
#guard rectOf [] 2 == some ⟨box.x, box.y + 32, box.w, 40⟩
#guard stacked []
-- A wheel tick of 1,616 points: the runtime lays rows 40 to 55, records their heights, and keeps
-- the first row showing (46) still as estimates turn into heights, which moves the offset to
-- 1,604. The app hears nothing of it.
def down : List Event := [.scroll box.center 0 1616]
#guard offset down == 1604
#guard laidKeys down == List.range' 40 16
#guard stacked down
#guard rectOf down 46 == some ⟨box.x, box.y, box.w, 40⟩
#guard st down == st []
-- A click on a row selects it, and it grows to 72 points: the rows under it move down, the
-- first showing stays.
def sel : List Event := down ++ ((rectOf down 47).map (click ·.center) |>.getD [])
#guard (st sel).selected == some 47
#guard rectOf sel 47 == some ⟨box.x, box.y + 40, box.w, 72⟩
#guard rectOf sel 48 == some ⟨box.x, box.y + 112, box.w, 24⟩
#guard rectOf sel 46 == rectOf down 46
#guard stacked sel
-- A row added at the top, while scrolled: every row on screen stays where it was.
def addAbove : List Event := down ++ clickOn (run down) addTopRef
#guard (st addAbove).keys[0]? == some 10001
#guard (List.range' 40 16).all fun k => rectOf addAbove k == rectOf down k
-- At the top too: row 1 stays at the top of the box, and the new row is just above it.
def addAbove0 : List Event := clickOn (run []) addTopRef
#guard offset addAbove0 == 32
#guard rectOf addAbove0 1 == rectOf [] 1
#guard rectOf addAbove0 10001 == some ⟨box.x, box.y - 32, box.w, 32⟩
-- A row added at the end goes above the end line.
#guard ((st (clickOn (run []) addEndRef)).keys.toList.drop 10000) == [10001, 0]
-- Far past the end: clamped to the end, where the end line shows and ^16 counts it, once per
-- visit. The content's length is an estimate until the rows are laid.
def far : List Event := [.scroll box.center 0 10000000]
#guard laidKeys far == List.range' 9991 10
#guard (find (run far).laid endRef).map (fun t => t.node.rect.y + t.node.rect.h) == some (box.y + box.h)
#guard (st far).ends == 1
#guard (st (far ++ [.scroll box.center 0 (-10)])).ends == 1
#guard (st down).ends == 0
#guard (((steps app tcfg (run far) [.scroll box.center 0 (-10000000)]).1 |>
  fun r => steps app tcfg r [.scroll box.center 0 10000000]).1.app.ends) == 2
#guard offset (far ++ [.scroll box.center 0 (-20000000)]) == 0
-- Keys move the box under the pointer: a page is the box less a line (120), End goes to the end.
#guard offset [.pointerMove box.center, .key .pageDown {}] == 120
#guard offset [.pointerMove box.center, .key .finish {}] == offset far
#guard offset [.pointerMove box.center, .key .finish {}, .key .home {}] == 0
-- Tab reaches only the rows laid: shift-Tab from nothing goes to the last of them.
#guard (run [.key .tab { shift := true }]).ui.focus == some (rowRef 10)
-- The frame names only the rows laid, draws only the five that show (rows 1 to 5 at the top),
-- and gives the box a node of its own.
def frame0 : Option Frame := decodeFrame (frameBytes Frame.boundary (run []))
#guard (frame0.map fun f => ((f.ax.toList.filterMap (·.control)).filter (·.claim == 10)).length) == some 10
#guard (frame0.map fun f => (f.draws.toList.filter fun
  | .text _ _ _ t => t.startsWith "Row " | _ => false).length) == some 5
#guard (frame0.map fun f => (f.ax.toList.filter (·.role == .scrollArea)).length) == some 1
-- endregion: fixture-scroll-tests

end Fixture.Tests
