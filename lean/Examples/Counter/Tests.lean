import Examples.Counter
import Cairn.Runtime

/-! Runtime checks for Counter: clicks in, through layout, hit testing and the v1 boundary, with
mono metrics (the interpreter can't call the host's Core Text). -/

namespace Examples.Counter.Tests
open Cairn Cairn.Runtime Examples.Counter

def tcfg : Config := {}
def run (es : List Event) : Runtime.State State := (steps app tcfg (start app tcfg ⟨480, 320⟩) es).1
def st (es : List Event) : State := (run es).app

/-- The centre of the control `r` on screen. -/
def at? (rs : Runtime.State State) (r : ControlRef) : Option Point :=
  (find rs.laid r).map (·.visible.center)
def clickOn (rs : Runtime.State State) (r : ControlRef) : List Event :=
  match at? rs r with
  | some p => [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}]
  | none => []

def clicks (r : ControlRef) : Nat → List Event
  | 0 => []
  | n + 1 => let es := clicks r n; es ++ clickOn (run es) r

-- region: counter-tests
#guard (st []).count == 0
#guard (at? (run []) resetRef).isNone
#guard (st (clicks incrementRef 3)).count == 3
#guard (at? (run (clicks incrementRef 3)) resetRef).isSome
def three : List Event := clicks incrementRef 3
#guard (st (three ++ clickOn (run three) resetRef)).count == 0
#guard (at? (run (three ++ clickOn (run three) resetRef)) resetRef).isNone
-- A press released off the control does nothing.
#guard (st (match at? (run []) incrementRef with
  | some p => [.pointerDown p .primary 1 {}, .pointerUp ⟨p.x + 300, p.y⟩ .primary {}]
  | none => [])).count == 0
-- Tab order: Increment, then Reset; Space on a focused button presses it.
#guard (tabOrder (run three).laid).map (·.ref) == [incrementRef, resetRef]
#guard (st (three ++ [.pointerExit, .key .tab {}, .key .tab {}, .insertText " "])).count == 0
-- The frame through the v1 boundary carries both controls, and the count as text.
#guard ((decodeFrame (frameBytes Frame.boundary (run three))).map fun f =>
  f.ax.toList.filterMap (·.control)) == some [incrementRef, resetRef]
-- endregion: counter-tests

end Examples.Counter.Tests
