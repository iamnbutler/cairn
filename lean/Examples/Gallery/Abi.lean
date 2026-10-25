module

public import Examples.Gallery
public import Cairn.Text.Host
public import Cairn.Runtime.Abi
public import Cairn.Abi

/-! # Gallery's v1 exports

In their own module, which only the `Gallery` library (and so `CairnGallery`) links. The host
starts it with `runtime_initialize_cairn_Examples_Gallery_Abi`. -/

@[expose] public section

namespace Examples.Gallery
open Cairn

/-- Core Text metrics in the running app (the Swift host links `cairn_text_metrics`). -/
def cfg : Runtime.Config := { metrics := TextMetrics.host }

@[export cairn_app_init]
def appInit (w h scalePercent : UInt32) : Runtime.State State :=
  Runtime.initState app cfg w h scalePercent

@[export cairn_app_step]
def appStep (s : Runtime.State State) (events : ByteArray) : Runtime.State State :=
  Runtime.stepBytes app cfg Frame.boundary s events

@[export cairn_app_frame]
def appFrame (s : Runtime.State State) : ByteArray := Runtime.frameBytes Frame.boundary s

end Examples.Gallery
