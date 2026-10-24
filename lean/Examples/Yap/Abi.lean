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

end Examples.Yap
