import Cairn.Claims.Core
import Cairn.Claims.Elab

/-! A second machine of the app's in a module that ends in `Claims` (../Clash.lean). -/

namespace Clash
open Cairn Cairn.Claims

structure State where
  n : Nat := 0

move ^2 bump (s : State) "Bump again" where
  does "Bump."
  sees "The count goes up."
  on press
    apply := { s with n := s.n + 1 }
    post s' := s'.n = s.n + 1
    sound := by intro s; rfl

def machine : Machine State := { init := {}, moves := moves% }

end Clash
