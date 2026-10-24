module

public import Examples.Yap
public import Cairn.Text.Host
public import Cairn.Runtime.Abi
public import Cairn.Frame.Boundary

/-! # Yap's exports

In their own module, which only the `Yap` library (and so `CairnYap`) links:
`Examples.lean` doesn't import it, so executables that link every example (the fuzzer) don't get
a second `cairn_app_init` beside Basics'. The host starts it with
`runtime_initialize_cairn_Examples_Yap_Abi`. -/

@[expose] public section

namespace Examples.Yap
open Cairn

/-! ## The app ABI (docs/runtime.md) -/

/-- Core Text metrics in the running app (the Swift host links `cairn_text_metrics`). -/
def cfg : Runtime.Config := { metrics := TextMetrics.host }

@[export cairn_app_init]
def appInit (w h scalePercent : UInt32) : Runtime.State AppState :=
  Runtime.initState app cfg w h scalePercent

@[export cairn_app_step]
def appStep (s : Runtime.State AppState) (events : ByteArray) : Runtime.State AppState :=
  Runtime.stepBytes app cfg Frame.boundary s events

@[export cairn_app_frame]
def appFrame (s : Runtime.State AppState) : ByteArray := Runtime.frameBytes Frame.boundary s

/-! ## The overlay in a given state, for the parity captures

`CairnYap --overlay-scenes` (docs/yap.md, "Overlay parity") renders the overlay offscreen in
the same states as the original's reference images. The scene is little-endian 32-bit words:
the look (0 listening, 1 hands free, 2 transcribing, 3 typed, 4 failed), `since`, `epoch`, the
clock now, the stop time (`0xFFFFFFFF` for none), the text's UTF-8 length and bytes, the level
count and (time, level) pairs, the cut count and cuts in samples. The answer is a frame (docs/frame.md)
with one surface, the panel at ^399, laid out as the app lays it out. -/

/-- The little-endian word at byte `i`. -/
def sceneWord (b : ByteArray) (i : Nat) : Nat :=
  (b.get! i).toNat + (b.get! (i + 1)).toNat * 256 + (b.get! (i + 2)).toNat * 65536 +
    (b.get! (i + 3)).toNat * 16777216

def scenePairs (b : ByteArray) (i : Nat) : Nat → List (Nat × Nat)
  | 0 => []
  | n + 1 => (sceneWord b i, sceneWord b (i + 4)) :: scenePairs b (i + 8) n

def sceneWords (b : ByteArray) (i : Nat) : Nat → List Nat
  | 0 => []
  | n + 1 => sceneWord b i :: sceneWords b (i + 4) n

def sceneOverlay (b : ByteArray) : Overlay × Nat :=
  let look : Look := match sceneWord b 0 with
    | 1 => .handsFree | 2 => .transcribing | 3 => .typed | 4 => .failed | _ => .listening
  let stop := sceneWord b 16
  let tl := sceneWord b 20
  let text := (String.fromUTF8? (b.extract 24 (24 + tl))).getD ""
  let i := 24 + tl
  let nl := sceneWord b i
  let levels := scenePairs b (i + 4) nl
  let j := i + 4 + 8 * nl
  let marks := (sceneWords b (j + 4) (sceneWord b j)).reverse
  ({ clip := 1, shown := true, look, text, since := sceneWord b 4, epoch := sceneWord b 8,
     stop := if stop = 0xFFFFFFFF then none else some stop, levels, marks }, sceneWord b 12)

@[export cairn_yap_overlay_frame]
def overlayFrame (scene : ByteArray) : ByteArray :=
  let (o, now) := sceneOverlay scene
  let s : AppState := { io := { overlay := o, mono := now } }
  match panel s with
  | none => Frame.boundary.encode { surfaces := #[] }
  | some pv =>
    let (sz, l) := Runtime.layPanel cfg pv
    Frame.boundary.encode
      { surfaces := #[{ kind := .panel, place := 399, anchor := pv.anchor, screen := pv.screen,
                        canvas := Frame.boundary.render l (Runtime.panelUI sz) }] }

end Examples.Yap
