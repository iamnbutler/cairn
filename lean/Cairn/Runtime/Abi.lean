module

public import Cairn.Runtime.Step
public import Cairn.Frame
public import Cairn.Frame.Menu

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

@[expose] public section

namespace Cairn.Runtime

/-- The byte formats at the boundary: `Cairn.Frame.boundary` (`Frame.ofLaid` and the v1
encoding, docs/frame.md). -/
structure Boundary where
  /-- Host event bytes → events, in order. -/
  decode : ByteArray → List Event
  /-- The draws, accessibility nodes and text input of a laid tree. It reads the `UI` for the
  surface's size and focus (the caret, `AxNode.focused`, `textInput`). The runtime fills in the
  cursor, the other surfaces and the effects. -/
  render : Laid → UI → Canvas
  encode : Frame → ByteArray

variable {S : Type}

def initState (app : App S) (cfg : Config) (w h scalePercent : UInt32) : State S :=
  start app cfg ⟨w.toNat, h.toNat⟩ scalePercent.toNat

/-- Run a batch of events. The state's `effects` become this batch's effects. -/
def stepBytes (app : App S) (cfg : Config) (b : Boundary) (s : State S) (events : ByteArray) :
    State S :=
  let (s', effs) := steps app cfg { s with effects := #[], subCmds := #[] } (b.decode events)
  { s' with effects := effs.toArray }

/-- A panel's `UI`: its size, and nothing focused, hovered or pressed (it takes no input). -/
def panelUI (size : Size) : UI := { size, windowFocused := false }

/-- One surface's record. The window shows the state's laid tree; a panel its own. -/
def surfaceFrame (b : Boundary) (s : State S) : Shown → SurfaceFrame
  | .window p t => { kind := .window, place := p, title := t,
                     canvas := { b.render s.laid s.ui with cursor := cursor s } }
  | .panel p none => { kind := .panel, place := p, shown := false }
  | .panel p (some (v, sz, l)) =>
    { kind := .panel, place := p, anchor := v.anchor, screen := v.screen,
      canvas := b.render l (panelUI sz) }
  | .status p none => { kind := .statusItem, place := p, shown := false }
  | .status p (some it) => { kind := .statusItem, place := p, status := Frame.ofStatus it }

def frame (b : Boundary) (s : State S) : Frame :=
  { surfaces := (s.surfaces.map (surfaceFrame b s)).toArray, effects := s.effects,
    subs := s.subCmds, wake := s.world.wake }

def frameBytes (b : Boundary) (s : State S) : ByteArray := b.encode (frame b s)

end Cairn.Runtime
