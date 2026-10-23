import Cairn.Runtime.Step
import Cairn.Frame

/-! The Lean side of the app ABI. The host (workstream G) loads one app per binary and calls
three exported functions; each app file defines them by applying these generic functions to
its `App`, a `Config` and a `Boundary`:

```lean
@[export cairn_app_init]
def appInit (w h scalePercent : UInt32) : Runtime.State MyApp.State :=
  Runtime.initState MyApp.app cfg w h scalePercent
@[export cairn_app_step]
def appStep (s : Runtime.State MyApp.State) (events : ByteArray) : Runtime.State MyApp.State :=
  Runtime.stepBytes MyApp.app cfg boundary s events
@[export cairn_app_frame]
def appFrame (s : Runtime.State MyApp.State) : ByteArray := Runtime.frameBytes boundary s
```

Lean 4.35 rejects `@&` on `@[export]`, so every argument is owned: the host passes its
reference to the state into `cairn_app_step` and keeps the one that comes back, and calls
`lean_inc` on the state before `cairn_app_frame` if it keeps using it. See docs/runtime.md. -/

namespace Cairn.Runtime

/-- The byte formats at the boundary. Workstream E supplies the real ones (`Frame.ofLaid` and
the v1 encoding); `Cairn.Runtime.Stub` has stand-ins. -/
structure Boundary where
  /-- Host event bytes → events, in order. -/
  decode : ByteArray → List Event
  /-- The draws, accessibility nodes and text input of a laid tree. The runtime fills in the
  cursor and effects. -/
  render : Laid → Size → Frame
  encode : Frame → ByteArray

variable {S : Type}

def initState (app : App S) (cfg : Config) (w h scalePercent : UInt32) : State S :=
  start app cfg ⟨w.toNat, h.toNat⟩ scalePercent.toNat

/-- Run a batch of events. The state's `effects` become this batch's effects. -/
def stepBytes (app : App S) (cfg : Config) (b : Boundary) (s : State S) (events : ByteArray) :
    State S :=
  let (s', effs) := steps app cfg { s with effects := #[] } (b.decode events)
  { s' with effects := effs.toArray }

def frame (b : Boundary) (s : State S) : Frame :=
  { b.render s.laid s.ui.size with cursor := cursor s, effects := s.effects }

def frameBytes (b : Boundary) (s : State S) : ByteArray := b.encode (frame b s)

end Cairn.Runtime
