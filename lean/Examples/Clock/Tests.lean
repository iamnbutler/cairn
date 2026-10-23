import Examples.Clock
import Cairn.Runtime

/-! Runtime checks for Clock: clock events, clicks, timers, replies and subscription events
through the runtime and the v1 boundary, with mono metrics. -/

namespace Examples.Clock.Tests
open Cairn Cairn.Runtime Examples.Clock

def tcfg : Config := {}
def s0 : Runtime.State State := start app tcfg ⟨480, 520⟩
def runFrom (s : Runtime.State State) (es : List Event) : Runtime.State State × List Effect :=
  steps app tcfg s es
def run (es : List Event) : Runtime.State State := (runFrom s0 es).1
def effs (es : List Event) : List Effect := (runFrom s0 es).2
def st (es : List Event) : State := (run es).app

def at? (rs : Runtime.State State) (r : ControlRef) : Option Point :=
  (find rs.laid r).map (·.visible.center)
def clickOn (rs : Runtime.State State) (r : ControlRef) : List Event :=
  match at? rs r with
  | some p => [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}]
  | none => []

def clock (ms : Nat) : Event := .clock { mono := ms, wall := 1700000000000 + ms, zone := 3600 }

/-- Events, then a click on `r` as laid out after them. -/
def thenClick (es : List Event) (r : ControlRef) : List Event := es ++ clickOn (run es) r

-- The first clock boots the app: it hears the time and reads the laps file (request 0), and
-- the subscription starts.
def boot : List Event := [clock 1000]
#guard (st boot).now == 1000
#guard effs boot == [.request 0 (.readFile lapsPath)]
#guard (run boot).subCmds.toList == [.start 1 (.every 1000)]
#guard (run boot).world.pending == [(0, .readFile)]
#guard reading 61234 == "1:01.2"
#guard timeOfDay 1700000000000 3600 == "23:13:20"
#guard parseLaps (lapsText [1200, 3400]).toUTF8 == some [1200, 3400]

-- The launch read finds no file: quietly nothing.
def booted : List Event := boot ++ [.reply 0 (.failed .notFound "")]
#guard (st booted).status == "" && (st booted).loading.isNone
#guard (run booted).world.pending.isEmpty

-- Start at 1000 ms: the tick is set 100 ms ahead and the frame asks to wake then.
def started : List Event := thenClick booted startStopRef
#guard (st started).running && (st started).since == 1000
#guard (runFrom (run booted) (clickOn (run booted) startStopRef)).2 == [.setTimer tick tickMs]
#guard (run started).world.wake == some 1100

-- The clock reaches 1100: the tick fires (after the time), re-arms, and the reading is 0.1 s.
def ticked : List Event := started ++ [clock 1100]
#guard elapsed (st ticked) == 100
#guard (run ticked).world.wake == some 1200
-- A clock before the deadline delivers nothing and leaves the app alone.
#guard (st (started ++ [clock 1050])) == st started

-- Lap at 1500 ms: a lap of 500 and a sound request.
def lapped : List Event := thenClick (ticked ++ [clock 1500]) lapRef
#guard (st lapped).laps == [500]
#guard (runFrom (run (ticked ++ [clock 1500])) (clickOn (run (ticked ++ [clock 1500])) lapRef)).2
  == [.request 1 (.playSound "Tink")]

-- Stop at 2000 ms: the tick is cancelled and never fires again.
def stopped : List Event := thenClick (lapped ++ [clock 2000]) startStopRef
#guard !(st stopped).running && elapsed (st stopped) == 1000
#guard (run stopped).world.timers.isEmpty && (run stopped).world.wake.isNone
#guard elapsed (st (stopped ++ [clock 5000])) == 1000

-- Save: a write request under a fresh id; its reply sets the status.
def saving : List Event := thenClick stopped saveRef
#guard (runFrom (run stopped) (clickOn (run stopped) saveRef)).2 ==
  [.request 2 (.writeFile lapsPath "500\n".toUTF8)]
#guard (st (saving ++ [.reply 2 .done])).status == "Saved 1 laps"
-- A reply in the wrong shape, or to an id nobody asked about, is dropped.
#guard (st (saving ++ [.reply 2 (.bytes ByteArray.empty)])).status == "Saving…"
#guard (st (saving ++ [.reply 9 .done])) == st saving
-- A reply is delivered once.
#guard (st (saving ++ [.reply 2 .done, .reply 2 (.failed .other "x")])).status == "Saved 1 laps"

-- Reset, then Load: the laps come back from the file's contents.
def reset : List Event := thenClick (saving ++ [.reply 2 .done]) resetRef
#guard (st reset).laps.isEmpty
def loading : List Event := thenClick reset loadRef
#guard (st (loading ++ [.reply 3 (.bytes "500\n".toUTF8)])).laps == [500]
#guard (st (loading ++ [.reply 3 (.bytes "500\n".toUTF8)])).status == "Loaded 1 laps"

-- Subscription events: id 1 is active; an unknown id is dropped.
#guard (st (booted ++ [.subEvent 1 .tick, clock 9000, .subEvent 1 .tick])).now == 9000
#guard (st (booted ++ [clock 9000, .subEvent 7 .tick])).now == 1000

-- The frame through the v1 boundary carries the wake and the subscription command.
#guard ((decodeFrame (frameBytes Frame.boundary (run started))).map (·.wake)) == some (some 1100)
#guard ((decodeFrame (frameBytes Frame.boundary (run boot))).map (·.subs.toList)) ==
  some [.start 1 (.every 1000)]

end Examples.Clock.Tests
