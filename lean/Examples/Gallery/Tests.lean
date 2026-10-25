import Examples.Gallery
import Cairn.Runtime
import Cairn.Frame.Build

/-! Runtime checks for Gallery: launch loads, replies, a stale reply, Reload and Fit through
the runtime, and the image draws in the frame, with mono metrics. -/

namespace Examples.Gallery.Tests
open Cairn Cairn.Runtime Examples.Gallery

def tcfg : Config := {}
def s0 : Runtime.State State := start app tcfg ⟨760, 560⟩
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
-- Two image draws, each in a 200 × 150 box; ridge (3:2) covers 200 × 150 as 225 × 150, centred (rounded down).
#guard (images loaded).length == 2
#guard (images loaded).all fun | .image r _ _ => r.w == 200 && r.h == 150 | _ => false
#guard (images loaded).head? == some (.image ⟨28, 80, 200, 150⟩ ⟨15, 80, 225, 150⟩ "images/ridge.png")

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

-- Fit: contain puts ridge's 3:2 inside the box as 200 × 133, centred.
def contained : List Event := thenClick (reloaded ++ [.reply 6 (.image 480 320)]) fitRef
#guard (st contained).fit == .contain
#guard (images contained).head? == some (.image ⟨28, 80, 200, 150⟩ ⟨28, 88, 200, 133⟩ "images/ridge.png")

end Examples.Gallery.Tests
