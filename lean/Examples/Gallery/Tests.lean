import Examples.Gallery
import Cairn.Runtime
import Cairn.Frame.Build

/-! Runtime checks for Gallery: launch loads, replies, a stale reply, Reload and Fit through
the runtime, Load 24 and Cancel against the cap, and the image draws in the frame, with mono
metrics. -/

namespace Examples.Gallery.Tests
open Cairn Cairn.Runtime Examples.Gallery

def tcfg : Config := {}
def s0 : Runtime.State State := start app tcfg ⟨1120, 560⟩
def runFrom (s : Runtime.State State) (es : List Event) : Runtime.State State × List Effect :=
  steps app tcfg s es
def run (es : List Event) : Runtime.State State := (runFrom s0 es).1
def effs (es : List Event) : List Effect := (runFrom s0 es).2
def st (es : List Event) : State := (run es).app

def clickOn (rs : Runtime.State State) (r : ControlRef) : List Event :=
  match (find rs.laid r).map (·.visible.center) with
  | some p => [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}]
  | none => []
def thenClick (es : List Event) (r : ControlRef) : List Event := es ++ clickOn (run es) r

def images (es : List Event) : List Draw :=
  (Frame.ofLaid (run es).ui (run es).laid).draws.toList.filter fun | .image .. => true | _ => false

def clock : Event := .clock { mono := 1000, wall := 1700000000000, zone := 0 }

-- The first clock asks for every source, under ids 0–5; nothing is drawn as an image yet.
def boot : List Event := [clock]
#guard effs boot == (sources.zipIdx.map fun (src, i) => .request i (.loadImage src false))
#guard (run boot).world.pending.length == 6
#guard images boot == []
#guard sources.all fun src => (st boot).images.state src == .loading

-- Replies: two sizes and a fault.
def loaded : List Event := boot ++ [.reply 0 (.image 480 320), .reply 1 (.image 480 320),
  .reply 4 (.failed .invalid "not an image"), .reply 5 (.failed .notFound "")]
#guard (st loaded).images.state "images/ridge.png" == .ready 480 320
#guard (st loaded).images.state "images/broken.png" == .failed .invalid "not an image"
#guard (st loaded).images.state "images/moss.gif" == .loading
-- Two image draws, each in a 196 × 147 box (a 4:3 card in the 3 × 2 grid at 1120 × 560); ridge
-- (3:2) covers it as 221 × 147, centred (rounded down).
#guard (images loaded).length == 2
#guard (images loaded).all fun | .image r _ _ => r.w == 196 && r.h == 147 | _ => false
#guard (images loaded).head? == some (.image ⟨54, 80, 196, 147⟩ ⟨41, 80, 221, 147⟩ "images/ridge.png")

-- Reload: every tile back to loading under ids 6–11, past the host's cache. Loads 2 and 3 were
-- still in flight, so they are cancelled; they keep their slots until the host answers them, so
-- only four of the six new loads go out at once (`App.maxInFlight` = 6) and two wait.
def reloaded : List Event := thenClick loaded reloadRef
#guard (st reloaded).reloads == 1 && (st reloaded).nextReq == 12
#guard sources.all fun src => (st reloaded).images.state src == .loading
#guard (runFrom (run loaded) (clickOn (run loaded) reloadRef)).2 ==
  [.cancelRequest 3, .cancelRequest 2] ++
  ((sources.zipIdx.take 4).map fun (src, i) => .request (i + 6) (.loadImage src true))
#guard (run reloaded).world.inFlight == 6 && (run reloaded).world.queued.length == 2
-- The cancelled load's late reply reaches no app (moss's id 2), and frees its slot: the next
-- waiting load goes out.
#guard (st (reloaded ++ [.reply 2 (.image 1 1)])).images.state "images/moss.gif" == .loading
#guard (runFrom (run reloaded) [.reply 2 (.image 1 1)]).2 ==
  [.request 10 (.loadImage "images/broken.png" true)]

-- Fit: contain puts ridge's 3:2 inside the box as 196 × 130, centred.
def contained : List Event := thenClick (reloaded ++ [.reply 6 (.image 480 320)]) fitRef
#guard (st contained).fit == .contain
#guard (images contained).head? == some (.image ⟨54, 80, 196, 147⟩ ⟨54, 88, 196, 130⟩ "images/ridge.png")

-- Load 24, with every tile loaded: six thumbnails go out (ids 6–11) and eighteen wait.
def settled : List Event := loaded ++ [.reply 2 (.image 1 1), .reply 3 (.image 1 1)]
def many : List Event := thenClick settled manyRef
#guard (run settled).world.inFlight == 0
#guard (runFrom (run settled) (clickOn (run settled) manyRef)).2 ==
  ((manySources.zipIdx.take 6).map fun (src, i) => .request (i + 6) (.loadImage src true))
#guard (run many).world.inFlight == 6 && (run many).world.queued.length == 18
#guard (manyCounts (st many)) == ("In flight 6 of 6 · queued 18", "Loaded 0 of 24 · cancelled 0")
-- One answer frees a slot; the next waiting thumbnail goes out.
#guard (runFrom (run many) [.reply 6 (.image 48 36)]).2 == [.request 12 (.loadImage (manySources.getD 6 "") true)]
def oneIn : List Event := many ++ [.reply 6 (.image 48 36)]
#guard (manyCounts (st oneIn)) == ("In flight 6 of 6 · queued 17", "Loaded 1 of 24 · cancelled 0")

-- Cancel: the six being fetched are cancelled on the frame; the seventeen waiting are dropped
-- without a word to the host. The cancelled six keep their slots until the host answers.
def cancelled : List Event := thenClick oneIn cancelRef
#guard (runFrom (run oneIn) (clickOn (run oneIn) cancelRef)).2 ==
  [.cancelRequest 12, .cancelRequest 11, .cancelRequest 10, .cancelRequest 9, .cancelRequest 8, .cancelRequest 7]
#guard (run cancelled).world.queued == [] && (run cancelled).world.inFlight == 6
#guard (manyCounts (st cancelled)) == ("In flight 0 of 6 · queued 0", "Loaded 1 of 24 · cancelled 23")
-- A late answer for a cancelled thumbnail changes nothing, sends nothing, and frees its slot.
#guard (st (cancelled ++ [.reply 7 (.image 48 36)])).images.state (manySources.getD 1 "") == .loading
#guard (runFrom (run cancelled) [.reply 7 (.image 48 36)]).2 == []
#guard (run (cancelled ++ [.reply 7 (.image 48 36)])).world.inFlight == 5

-- The tile grid follows the window: three columns at 1120 wide, five at 1600, and a resize
-- reflows the laid tiles onto the new `tileRects`.
def cols (sz : Size) : Nat := tileGrid.columns (gridW sz)
#guard cols ⟨1120, 560⟩ == 3 && cols ⟨1600, 900⟩ == 5 && cols ⟨900, 640⟩ == 2
def tileCells (rs : Runtime.State State) : List Rect :=
  (((rs.laid.children.headD default).children.getD 1 default).children.flatMap (·.children)).map (·.rect)
#guard tileCells s0 == tileRects ⟨1120, 560⟩
def wide : Runtime.State State := (runFrom s0 [.resize ⟨1600, 900⟩]).1
#guard tileCells wide == tileRects ⟨1600, 900⟩
#guard (tileRects ⟨1600, 900⟩).map (·.x) == [28, 264, 500, 736, 972, 28]

-- A tile's press reloads that tile alone, past the cache, under the next id.
def tileOne : List Event := thenClick settled (tileRef 1)
#guard (runFrom (run settled) (clickOn (run settled) (tileRef 1))).2 ==
  [.request 6 (.loadImage "images/tide.jpg" true)]
#guard (st tileOne).images.state "images/tide.jpg" == .loading
#guard (st tileOne).images.state "images/ridge.png" == .ready 480 320

end Examples.Gallery.Tests
