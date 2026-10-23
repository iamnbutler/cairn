import Examples.Clock
import Cairn.Claims.Deliver

/-! # Clock: theorems through the runtime

The moves' evidence and the invariant ^409 are checked where they are declared, in
`Examples.Clock`; ^409 is kept by `receive` as well as by every move. Here it is carried
through the runtime: it holds in every state the running app reaches, whatever input, clock
events, timer firings, replies and subscription events arrive, in any order. -/

namespace Examples.Clock
open Cairn Cairn.Claims Cairn.Runtime

/-- ^409 on screen: after any events, every pending save or load has an id below the next
request's, so no later request can be answered in its place. -/
theorem freshRequests_on_screen (cfg : Config) (size : Size) (scale : Nat) (es : List Event) :
    freshRequests.holds (steps app cfg (start app cfg size scale) es).1.app :=
  freshRequests.reachableAll _ (steps_reachableAll machine app rfl rfl rfl cfg size scale es)

end Examples.Clock
